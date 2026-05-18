use libboss_rs_core::{product_for_id, ProductInfoCommands, ProductInfoParser};

use crate::{
    BootstrapSessionError, BootstrapTimeoutError, BossLink, BossSessionError, BootstrappedDevice,
    PacketSession, SessionConfiguration,
};

pub struct BootstrapSession<L: BossLink> {
    packet_session: PacketSession<L>,
    configuration: SessionConfiguration,
}

impl<L: BossLink> BootstrapSession<L> {
    pub fn new(link: L, configuration: SessionConfiguration) -> Self {
        Self {
            packet_session: PacketSession::new(link),
            configuration,
        }
    }

    pub async fn bootstrap(&self) -> Result<BootstrappedDevice, BootstrapSessionError> {
        let version_request = ProductInfoCommands::bmap_version(
            self.configuration.default_device_id,
            self.configuration.default_port,
        );

        let version_response = match self
            .packet_session
            .response_packet_for_function(
                &version_request,
                &version_request.function,
                self.configuration.first_version_timeout_millis,
            )
            .await
        {
            Ok(response) => response,
            Err(BossSessionError::ResponseTimedOut { .. }) => {
                self.packet_session
                    .response_packet_for_function(
                        &version_request,
                        &version_request.function,
                        self.configuration.retry_version_timeout_millis,
                    )
                    .await
                    .map_err(|error| {
                        BootstrapSessionError::from_session_error_with_timeout(
                            error,
                            BootstrapTimeoutError::BmapVersion {
                                timeout_milliseconds: self.configuration.retry_version_timeout_millis,
                            },
                        )
                    })?
            }
            Err(error) => {
                return Err(BootstrapSessionError::from_session_error_with_timeout(
                    error,
                    BootstrapTimeoutError::BmapVersion {
                        timeout_milliseconds: self.configuration.first_version_timeout_millis,
                    },
                ))
            }
        };
        let version_info = ProductInfoParser::parse_bmap_version(&version_response)?;

        let product_request = ProductInfoCommands::product_id_variant(
            self.configuration.default_device_id,
            self.configuration.default_port,
        );
        let product_packet = self
            .packet_session
            .response_packet_for_function(
                &product_request,
                &product_request.function,
                self.configuration.request_timeout_millis,
            )
            .await
            .map_err(|error| {
                BootstrapSessionError::from_session_error_with_timeout(
                    error,
                    BootstrapTimeoutError::Packet {
                        function: product_request.function.name(),
                        timeout_milliseconds: self.configuration.request_timeout_millis,
                    },
                )
            })?;
        let product_variant = ProductInfoParser::parse_product_id_variant(&product_packet)?;

        let block_request = ProductInfoCommands::all_function_blocks_get(
            self.configuration.default_device_id,
            self.configuration.default_port,
        );
        let blocks_packet = self
            .packet_session
            .response_packet_for_function(
                &block_request,
                &block_request.function,
                self.configuration.request_timeout_millis,
            )
            .await
            .map_err(|error| {
                BootstrapSessionError::from_session_error_with_timeout(
                    error,
                    BootstrapTimeoutError::Packet {
                        function: block_request.function.name(),
                        timeout_milliseconds: self.configuration.request_timeout_millis,
                    },
                )
            })?;
        let function_blocks = ProductInfoParser::parse_function_blocks(&blocks_packet)?;

        Ok(BootstrappedDevice {
            bmap_version: version_info,
            product_id: product_variant.product_id,
            product_name: product_for_id(product_variant.product_id)
                .map(|product| product.display_name.to_string())
                .unwrap_or_else(|| "Unknown Bose Product".into()),
            product_variant,
            supported_function_blocks: function_blocks,
            transport_kind: self.packet_session.transport_kind(),
            default_device_id: self.configuration.default_device_id,
            default_port: self.configuration.default_port,
        })
    }
}

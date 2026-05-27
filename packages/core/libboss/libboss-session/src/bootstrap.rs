use libboss_core::{
    product_for_id, implied_function_blocks_for_product, BmapErrorCode, BossDeviceCapabilities,
    BossProtocolSupport, ProductInfoCommands, ProductInfoParser,
};

use crate::{
    BootstrapSessionError, BootstrapTimeoutError, BootstrappedDevice, BossLink, BossSessionError,
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
            Err(BossSessionError::ResponseTimedOut { .. }) => self
                .packet_session
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
                })?,
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
        let catalog_product = product_variant.product;

        let block_request = ProductInfoCommands::all_function_blocks_get(
            self.configuration.default_device_id,
            self.configuration.default_port,
        );
        let function_blocks = match self
            .packet_session
            .response_packet(&block_request, self.configuration.request_timeout_millis)
            .await
        {
            Ok(blocks_packet) => ProductInfoParser::parse_function_blocks(&blocks_packet)?,
            Err(BossSessionError::BmapErrorResponse(response))
                if matches!(
                    response.code(),
                    Some(BmapErrorCode::FblockNotSupp | BmapErrorCode::FuncNotSupp)
                ) =>
            {
                implied_function_blocks_for_product(catalog_product).ok_or_else(|| {
                    BootstrapSessionError::Session(BossSessionError::BmapErrorResponse(response))
                })?
            }
            Err(error) => {
                return Err(BootstrapSessionError::from_session_error_with_timeout(
                    error,
                    BootstrapTimeoutError::Packet {
                        function: block_request.function.name(),
                        timeout_milliseconds: self.configuration.request_timeout_millis,
                    },
                ))
            }
        };
        let protocol_support = BossProtocolSupport {
            function_blocks,
            transport_kind: self.packet_session.transport_kind(),
            default_device_id: self.configuration.default_device_id,
            default_port: self.configuration.default_port,
        };
        let capabilities = BossDeviceCapabilities::resolve(catalog_product, &protocol_support);

        Ok(BootstrappedDevice {
            bmap_version: version_info,
            product_id: product_variant.product_id,
            product_name: product_for_id(product_variant.product_id)
                .map(|product| product.display_name.to_string())
                .unwrap_or_else(|| "Unknown Bose Product".into()),
            product_variant,
            protocol_support,
            capabilities,
        })
    }
}

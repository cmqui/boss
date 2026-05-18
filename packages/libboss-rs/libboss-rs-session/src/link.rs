use async_trait::async_trait;
use libboss_rs_core::{BmapPacket, BossTransportKind};

use crate::BossLinkError;

#[async_trait]
pub trait BossLink: Send + Sync {
    fn transport_kind(&self) -> BossTransportKind;
    async fn send_packet(&self, packet: &BmapPacket) -> Result<(), BossLinkError>;
    async fn next_packet(&self, timeout_millis: u64) -> Result<Option<BmapPacket>, BossLinkError>;
}

#[cfg(test)]
use std::collections::VecDeque;
#[cfg(test)]
use std::sync::{Arc, Mutex};

#[cfg(test)]
use async_trait::async_trait;
#[cfg(test)]
use libboss_rs_core::{BmapPacket, BossTransportKind};

#[cfg(test)]
use crate::{BossLink, BossLinkError};

#[cfg(test)]
#[derive(Clone)]
pub struct MockLink {
    transport_kind: BossTransportKind,
    packets: Arc<Mutex<VecDeque<Result<Option<BmapPacket>, BossLinkError>>>>,
    sent_packets: Arc<Mutex<Vec<BmapPacket>>>,
}

#[cfg(test)]
impl MockLink {
    pub fn new(packets: Vec<Result<Option<BmapPacket>, BossLinkError>>) -> Self {
        Self {
            transport_kind: BossTransportKind::Stream,
            packets: Arc::new(Mutex::new(VecDeque::from(packets))),
            sent_packets: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn sent_packets(&self) -> Vec<BmapPacket> {
        self.sent_packets.lock().unwrap().clone()
    }
}

#[cfg(test)]
#[async_trait]
impl BossLink for MockLink {
    fn transport_kind(&self) -> BossTransportKind {
        self.transport_kind
    }

    async fn send_packet(&self, packet: &BmapPacket) -> Result<(), BossLinkError> {
        self.sent_packets.lock().unwrap().push(packet.clone());
        Ok(())
    }

    async fn next_packet(&self, _timeout_millis: u64) -> Result<Option<BmapPacket>, BossLinkError> {
        self.packets.lock().unwrap().pop_front().unwrap_or(Ok(None))
    }
}

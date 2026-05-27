#[cfg(test)]
use std::collections::VecDeque;
#[cfg(test)]
use std::sync::{Arc, Mutex};

#[cfg(test)]
use async_trait::async_trait;
#[cfg(test)]
use libboss_core::{BmapPacket, BossTransportKind};

#[cfg(test)]
use crate::{BossLink, BossLinkError};

#[cfg(test)]
#[derive(Clone)]
pub struct MockLink {
    transport_kind: BossTransportKind,
    packets: Arc<Mutex<VecDeque<Result<Option<BmapPacket>, BossLinkError>>>>,
    sent_packets: Arc<Mutex<Vec<BmapPacket>>>,
    next_packet_call_count: Arc<Mutex<usize>>,
}

#[cfg(test)]
impl MockLink {
    pub fn new(packets: Vec<Result<Option<BmapPacket>, BossLinkError>>) -> Self {
        Self {
            transport_kind: BossTransportKind::Stream,
            packets: Arc::new(Mutex::new(VecDeque::from(packets))),
            sent_packets: Arc::new(Mutex::new(Vec::new())),
            next_packet_call_count: Arc::new(Mutex::new(0)),
        }
    }

    pub fn sent_packets(&self) -> Vec<BmapPacket> {
        self.sent_packets.lock().unwrap().clone()
    }

    pub fn next_packet_call_count(&self) -> usize {
        *self.next_packet_call_count.lock().unwrap()
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
        *self.next_packet_call_count.lock().unwrap() += 1;
        self.packets.lock().unwrap().pop_front().unwrap_or(Ok(None))
    }
}

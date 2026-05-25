use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, OnceLock, Weak};
use std::thread;

use async_trait::async_trait;
use libboss_core::{BmapPacket, BossTransportKind};
use libboss_session::{BossLink, BossLinkError};

use crate::host_link::{ffi_link_from_callbacks, FfiLink};
use crate::{BossFfiError, BossFfiSessionCallbacks};

const BROKER_POLL_TIMEOUT_MILLIS: u64 = 250;

#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq)]
struct BrokerKey {
    context: usize,
    transport_kind: u8,
    send_packet_bytes: usize,
    next_packet_bytes: usize,
    release_context: usize,
}

impl BrokerKey {
    fn new(callbacks: &BossFfiSessionCallbacks) -> Self {
        Self {
            context: callbacks.context as usize,
            transport_kind: callbacks.transport_kind,
            send_packet_bytes: callbacks
                .send_packet_bytes
                .map(|callback| callback as usize)
                .unwrap_or_default(),
            next_packet_bytes: callbacks
                .next_packet_bytes
                .map(|callback| callback as usize)
                .unwrap_or_default(),
            release_context: callbacks
                .release_context
                .map(|callback| callback as usize)
                .unwrap_or_default(),
        }
    }
}

#[derive(Clone)]
enum BrokerEvent {
    Packet(BmapPacket),
    StreamEnded,
    UnexpectedStreamTermination,
    OtherError(String),
}

struct BrokerState {
    next_sequence: u64,
    base_sequence: u64,
    events: VecDeque<BrokerEvent>,
    cursors: HashMap<u64, u64>,
}

impl BrokerState {
    fn trim_consumed(&mut self) {
        let Some(min_sequence) = self.cursors.values().copied().min() else {
            self.events.clear();
            self.base_sequence = self.next_sequence;
            return;
        };
        while self.base_sequence < min_sequence && !self.events.is_empty() {
            self.events.pop_front();
            self.base_sequence += 1;
        }
    }

    fn event_at(&self, sequence: u64) -> Option<BrokerEvent> {
        if sequence < self.base_sequence {
            return None;
        }
        let index = usize::try_from(sequence - self.base_sequence).ok()?;
        self.events.get(index).cloned()
    }
}

struct SharedState {
    state: Mutex<BrokerState>,
    ready: Condvar,
}

pub(crate) struct UpdateBroker {
    link: FfiLink,
    shared: Arc<SharedState>,
    next_subscriber_id: AtomicU64,
    closed: Arc<AtomicBool>,
}

impl UpdateBroker {
    fn acquire(
        callbacks: BossFfiSessionCallbacks,
        out_error: *mut BossFfiError,
    ) -> Option<Arc<Self>> {
        let key = BrokerKey::new(&callbacks);
        let registry = broker_registry();

        {
            let mut entries = registry.lock().unwrap();
            if let Some(existing) = entries.get(&key).and_then(Weak::upgrade) {
                drop(entries);
                release_callbacks_context(callbacks);
                return Some(existing);
            }

            let link = ffi_link_from_callbacks(callbacks, out_error)?;
            let broker = Arc::new(Self::new(link));
            entries.insert(key, Arc::downgrade(&broker));
            return Some(broker);
        }
    }

    fn new(link: FfiLink) -> Self {
        let broker = Self {
            link,
            shared: Arc::new(SharedState {
                state: Mutex::new(BrokerState {
                    next_sequence: 0,
                    base_sequence: 0,
                    events: VecDeque::new(),
                    cursors: HashMap::new(),
                }),
                ready: Condvar::new(),
            }),
            next_subscriber_id: AtomicU64::new(1),
            closed: Arc::new(AtomicBool::new(false)),
        };
        broker.spawn_reader();
        broker
    }

    pub(crate) fn transport_kind(&self) -> BossTransportKind {
        self.link.transport_kind()
    }

    pub(crate) fn subscribe(self: &Arc<Self>) -> BrokerSubscriber {
        let subscriber_id = self.next_subscriber_id.fetch_add(1, Ordering::Relaxed);
        let mut state = self.shared.state.lock().unwrap();
        let next_sequence = state.base_sequence;
        state.cursors.insert(subscriber_id, next_sequence);
        drop(state);
        BrokerSubscriber {
            broker: Arc::clone(self),
            subscriber_id,
            next_sequence,
        }
    }

    fn spawn_reader(&self) {
        let shared = Arc::clone(&self.shared);
        let link = self.link.clone();
        let closed = self.closed.clone();
        thread::spawn(move || {
            while !closed.load(Ordering::Relaxed) {
                match futures::executor::block_on(link.next_packet(BROKER_POLL_TIMEOUT_MILLIS)) {
                    Ok(Some(packet)) => push_event(&shared, BrokerEvent::Packet(packet)),
                    Ok(None) => {
                        push_event(&shared, BrokerEvent::StreamEnded);
                        return;
                    }
                    Err(BossLinkError::TimedOut) => continue,
                    Err(BossLinkError::UnexpectedStreamTermination) => {
                        push_event(&shared, BrokerEvent::UnexpectedStreamTermination);
                        return;
                    }
                    Err(BossLinkError::Other(message)) => {
                        push_event(&shared, BrokerEvent::OtherError(message));
                        return;
                    }
                }
            }
        });
    }
}

impl Drop for UpdateBroker {
    fn drop(&mut self) {
        self.closed.store(true, Ordering::Relaxed);
        self.shared.ready.notify_all();
    }
}

pub(crate) struct BrokerSubscriber {
    broker: Arc<UpdateBroker>,
    subscriber_id: u64,
    next_sequence: u64,
}

impl BrokerSubscriber {
    pub(crate) fn next_packet(&mut self, timeout_millis: u64) -> Result<Option<BmapPacket>, BossLinkError> {
        self.next_matching(timeout_millis, |_| true)
    }

    pub(crate) fn next_matching(
        &mut self,
        timeout_millis: u64,
        predicate: impl Fn(&BmapPacket) -> bool,
    ) -> Result<Option<BmapPacket>, BossLinkError> {
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(timeout_millis);
        let mut state = self.broker.shared.state.lock().unwrap();

        loop {
            while let Some(event) = state.event_at(self.next_sequence) {
                self.next_sequence += 1;
                state.cursors.insert(self.subscriber_id, self.next_sequence);
                state.trim_consumed();
                match event {
                    BrokerEvent::Packet(packet) => {
                        if predicate(&packet) {
                            return Ok(Some(packet));
                        }
                    }
                    BrokerEvent::StreamEnded => return Ok(None),
                    BrokerEvent::UnexpectedStreamTermination => {
                        return Err(BossLinkError::UnexpectedStreamTermination);
                    }
                    BrokerEvent::OtherError(message) => return Err(BossLinkError::Other(message)),
                }
            }

            let Some(remaining) = deadline.checked_duration_since(std::time::Instant::now()) else {
                return Err(BossLinkError::TimedOut);
            };
            let (updated_state, timeout_result) = self
                .broker
                .shared
                .ready
                .wait_timeout(state, remaining)
                .unwrap();
            state = updated_state;
            if timeout_result.timed_out() {
                return Err(BossLinkError::TimedOut);
            }
        }
    }
}

impl Drop for BrokerSubscriber {
    fn drop(&mut self) {
        let mut state = self.broker.shared.state.lock().unwrap();
        state.cursors.remove(&self.subscriber_id);
        state.trim_consumed();
        drop(state);
        self.broker.shared.ready.notify_all();
    }
}

#[derive(Clone)]
pub(crate) struct BrokerPacketLink {
    broker: Arc<UpdateBroker>,
    subscriber: Arc<Mutex<BrokerSubscriber>>,
}

impl BrokerPacketLink {
    pub(crate) fn new(broker: Arc<UpdateBroker>) -> Self {
        Self {
            subscriber: Arc::new(Mutex::new(broker.subscribe())),
            broker,
        }
    }
}

#[async_trait]
impl BossLink for BrokerPacketLink {
    fn transport_kind(&self) -> BossTransportKind {
        self.broker.transport_kind()
    }

    async fn send_packet(&self, packet: &BmapPacket) -> Result<(), BossLinkError> {
        self.broker.link.send_packet(packet).await
    }

    async fn next_packet(&self, timeout_millis: u64) -> Result<Option<BmapPacket>, BossLinkError> {
        self.subscriber.lock().unwrap().next_packet(timeout_millis)
    }
}

fn broker_registry() -> &'static Mutex<HashMap<BrokerKey, Weak<UpdateBroker>>> {
    static REGISTRY: OnceLock<Mutex<HashMap<BrokerKey, Weak<UpdateBroker>>>> = OnceLock::new();
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn push_event(shared: &SharedState, event: BrokerEvent) {
    let mut state = shared.state.lock().unwrap();
    state.events.push_back(event);
    state.next_sequence += 1;
    shared.ready.notify_all();
}

fn release_callbacks_context(callbacks: BossFfiSessionCallbacks) {
    if let Some(release_context) = callbacks.release_context {
        release_context(callbacks.context);
    }
}

pub(crate) fn broker_packet_link_from_callbacks(
    callbacks: BossFfiSessionCallbacks,
    out_error: *mut BossFfiError,
) -> Option<BrokerPacketLink> {
    let broker = UpdateBroker::acquire(callbacks, out_error)?;
    Some(BrokerPacketLink::new(broker))
}

pub(crate) fn broker_stream_parts_from_callbacks(
    callbacks: BossFfiSessionCallbacks,
    out_error: *mut BossFfiError,
) -> Option<(BrokerPacketLink, BrokerSubscriber)> {
    let broker = UpdateBroker::acquire(callbacks, out_error)?;
    let link = BrokerPacketLink::new(broker.clone());
    let subscriber = broker.subscribe();
    Some((link, subscriber))
}

use std::collections::BTreeMap;

use crate::{BleReassemblyError, BleSegmentationError, BmapCodec, BmapPacket, Bytes, PacketDecodeError};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BossTransportKind {
    Ble,
    Stream,
}

pub struct BleSegmentation;

impl BleSegmentation {
    pub fn encode(packet_bytes: &[u8], mtu: usize) -> Result<Vec<Bytes>, BleSegmentationError> {
        if mtu < 4 {
            return Err(BleSegmentationError::InvalidMtu(mtu));
        }
        let chunk_size = mtu - 4;
        if packet_bytes.len() <= chunk_size {
            let mut frame = vec![0x00];
            frame.extend_from_slice(packet_bytes);
            return Ok(vec![frame]);
        }
        let segment_count = packet_bytes.len().div_ceil(chunk_size);
        if segment_count > 16 {
            return Err(BleSegmentationError::TooManySegments(segment_count));
        }
        let max_index = segment_count - 1;
        let mut frames = Vec::with_capacity(segment_count);
        for segment_index in 0..segment_count {
            let start = segment_index * chunk_size;
            let end = usize::min(start + chunk_size, packet_bytes.len());
            let mut frame = vec![((max_index as u8) << 4) | (segment_index as u8)];
            frame.extend_from_slice(&packet_bytes[start..end]);
            frames.push(frame);
        }
        Ok(frames)
    }
}

#[derive(Debug, Default, Clone)]
pub struct BleSegmentReassembler {
    segments: BTreeMap<usize, Bytes>,
    expected_max_index: Option<usize>,
    chunk_size: Option<usize>,
}

impl BleSegmentReassembler {
    pub fn push(&mut self, segment: &[u8]) -> Result<Option<Bytes>, BleReassemblyError> {
        let Some(header) = segment.first().copied() else {
            return Err(BleReassemblyError::EmptySegment);
        };
        if segment.len() < 2 {
            return Err(BleReassemblyError::SegmentTooShort(segment.len()));
        }
        if header == 0x00 {
            self.reset();
            return Ok(Some(segment[1..].to_vec()));
        }
        let max_index = ((header >> 4) & 0x0F) as usize;
        let segment_index = (header & 0x0F) as usize;
        if segment_index > max_index {
            return Err(BleReassemblyError::InvalidSegmentIndex(segment_index));
        }
        if let Some(expected) = self.expected_max_index {
            if expected != max_index {
                return Err(BleReassemblyError::InconsistentSegmentSeries { expected_max_index: expected, actual_max_index: max_index });
            }
        }
        if self.segments.contains_key(&segment_index) {
            return Err(BleReassemblyError::DuplicateSegmentIndex(segment_index));
        }
        self.expected_max_index = Some(max_index);
        self.chunk_size.get_or_insert(segment.len() - 1);
        self.segments.insert(segment_index, segment[1..].to_vec());
        if segment_index != max_index {
            return Ok(None);
        }
        let expected_count = max_index + 1;
        if self.segments.len() != expected_count {
            return Err(BleReassemblyError::MissingSegments { expected: expected_count, actual: self.segments.len() });
        }
        let chunk_size = self.chunk_size.unwrap_or(0);
        let mut output = Vec::new();
        for index in 0..expected_count {
            let Some(chunk) = self.segments.get(&index) else {
                return Err(BleReassemblyError::MissingSegments { expected: expected_count, actual: self.segments.len() });
            };
            if index < max_index && chunk.len() != chunk_size {
                return Err(BleReassemblyError::SegmentTooShort(chunk.len() + 1));
            }
            output.extend_from_slice(chunk);
        }
        self.reset();
        Ok(Some(output))
    }

    fn reset(&mut self) {
        self.segments.clear();
        self.expected_max_index = None;
        self.chunk_size = None;
    }
}

#[derive(Debug, Default, Clone)]
pub struct BmapFrameStreamDecoder {
    buffer: Bytes,
}

impl BmapFrameStreamDecoder {
    pub fn push(&mut self, chunk: &[u8]) -> Result<Vec<BmapPacket>, PacketDecodeError> {
        self.buffer.extend_from_slice(chunk);
        let mut packets = Vec::new();
        while self.buffer.len() >= BmapPacket::HEADER_SIZE {
            let payload_length = self.buffer[3] as usize;
            let packet_length = BmapPacket::HEADER_SIZE + payload_length;
            if self.buffer.len() < packet_length {
                break;
            }
            let packet = BmapCodec::decode(&self.buffer[..packet_length])?;
            packets.push(packet);
            self.buffer.drain(..packet_length);
        }
        Ok(packets)
    }
}

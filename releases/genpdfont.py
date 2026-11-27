#!/usr/bin/env python3
"""Remap Unifont Upper to the BMP for the 16-bit Free Pascal PDF font reader."""

import gzip
import struct
import sys
from pathlib import Path


def checksum(data):
    return sum(value for value, in struct.iter_unpack('>I', data + bytes(-len(data) % 4))) & 0xffffffff


def build(data):
    u16 = lambda offset: struct.unpack_from('>H', data, offset)[0]
    tables = {}
    for index in range(u16(4)):
        tag, _, offset, length = struct.unpack_from('>4sIII', data, 12 + index * 16)
        tables[tag] = data[offset:offset + length]
    cmap = tables[b'cmap']
    for index in range(struct.unpack_from('>H', cmap, 2)[0]):
        _, _, offset = struct.unpack_from('>HHI', cmap, 4 + index * 8)
        if struct.unpack_from('>H', cmap, offset)[0] == 12:
            break
    else:
        raise ValueError('Unifont Upper has no supplementary cmap')

    source_groups = struct.unpack_from('>I', cmap, offset + 12)[0]
    packed_ranges = []
    segments = []
    code = 0x100
    for index in range(source_groups):
        first, last, glyph = struct.unpack_from('>III', cmap, offset + 16 + index * 12)
        while first <= last and first >= 0x10000:
            if code == 0xd800:
                code = 0xe000
            limit = 0xd800 if code < 0xd800 else 0xffff
            count = min(last - first + 1, limit - code)
            if count <= 0:
                raise ValueError('Too many supplemental characters for the remapped font')
            packed_ranges.append((first, first + count - 1, code))
            segments.append((code, code + count - 1, (glyph - code) & 0xffff))
            first += count
            glyph += count
            code += count
    segments.append((0xffff, 0xffff, 1))
    count = len(segments)
    power = 1 << (count.bit_length() - 1)
    body = struct.pack('>7H', 4, 16 + 8 * count, 0, 2 * count, 2 * power, power.bit_length() - 1, 2 * (count - power))
    body += struct.pack(f'>{count}H', *(end for _, end, _ in segments)) + bytes(2)
    body += struct.pack(f'>{count}H', *(start for start, _, _ in segments))
    body += struct.pack(f'>{count}H', *(delta for _, _, delta in segments)) + bytes(2 * count)
    tables[b'cmap'] = struct.pack('>HHHHI', 0, 1, 3, 1, 12) + body
    head = bytearray(tables[b'head'])
    head[8:12] = bytes(4)
    tables[b'head'] = head

    count = len(tables)
    power = 1 << (count.bit_length() - 1)
    result = bytearray(data[:4] + struct.pack('>4H', count, 16 * power, power.bit_length() - 1, 16 * (count - power)))
    chunks = bytearray()
    for tag, table in sorted(tables.items()):
        position = 12 + count * 16 + len(chunks)
        if tag == b'head':
            head_pos = position
        result.extend(struct.pack('>4sIII', tag, checksum(table), position, len(table)))
        chunks.extend(table)
        chunks.extend(bytes(-len(table) % 4))
    result.extend(chunks)
    struct.pack_into('>I', result, head_pos + 8, (0xb1b0afba - checksum(result)) & 0xffffffff)
    mapping = struct.pack('>H', len(packed_ranges))
    mapping += b''.join(struct.pack('>IIH', *entry) for entry in packed_ranges)
    return mapping + result


if __name__ == '__main__':
    source, output = map(Path, sys.argv[1:])
    data = source.read_bytes()
    if data.startswith(b'\x1f\x8b'):
        data = gzip.decompress(data)
    output.write_bytes(gzip.compress(build(data), compresslevel=9, mtime=0))

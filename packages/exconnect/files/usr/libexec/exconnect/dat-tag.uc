'use strict';

import { open } from 'fs';

let file;
let position = 0;

function byte(limit) {
	assert(position < limit, 'Truncated DAT field');
	let data = file.read(1);
	assert(data != null && length(data) == 1, 'Could not read DAT field');
	position++;
	return ord(data);
}

// Lengths are bounded by the actual file, while field keys are uint32 values.
function varint(limit, maximum) {
	let value = 0;
	let factor = 1;
	for (let i = 0; i < 10; i++) {
		let next = byte(limit);
		let part = next & 127;
		if (i == 9) {
			assert(next == 0, 'DAT integer is out of range');
			return value;
		}
		assert(part == 0 || factor <= maximum / part, 'DAT integer is out of range');
		let term = part * factor;
		assert(value <= maximum - term, 'DAT integer is out of range');
		value += term;
		if (!(next & 128))
			return value;
		if (i < 8)
			factor *= 128;
	}
	assert(false, 'Invalid DAT integer');
}

function skip(count, limit) {
	assert(count >= 0 && count <= limit - position, 'Truncated DAT field');
	position += count;
	assert(file.seek(position), 'Could not seek in DAT file');
}

function skipField(wire, limit) {
	switch (wire) {
	case 0:
		for (let i = 0; i < 10; i++) {
			let next = byte(limit);
			assert(i < 9 || next < 2, 'Invalid DAT integer');
			if (!(next & 128))
				return;
		}
		assert(false, 'Invalid DAT integer');
		break;
	case 1:
		skip(8, limit);
		break;
	case 2:
		let size = varint(limit, limit - position);
		skip(size, limit);
		break;
	case 5:
		skip(4, limit);
		break;
	default:
		assert(false, 'Unsupported DAT field type');
	}
}

function entryTag(limit) {
	while (position < limit) {
		let key = varint(limit, 4294967295);
		assert(key >= 8, 'Invalid DAT field number');
		if (key == 10) {
			let size = varint(limit, limit - position);
			assert(size <= limit - position, 'Truncated DAT tag');
			if (size == 0)
				continue;
			let tag = file.read(size);
			assert(tag != null && length(tag) == size, 'Could not read DAT tag');
			position += size;
			assert(!match(tag, /[[:cntrl:]:]/), 'DAT tag cannot be used in an Xray rule');
			return tag;
		}
		skipField(key & 7, limit);
	}
	return null;
}

try {
	file = open(ARGV[0], 'r');
	assert(file && file.seek(0, 2), 'Could not open DAT file');
	let size = file.tell();
	assert(size != null && size > 0 && file.seek(0), 'DAT file is empty or unreadable');
	while (position < size) {
		let key = varint(size, 4294967295);
		assert(key >= 8, 'Invalid DAT field number');
		if (key != 10) {
			skipField(key & 7, size);
			continue;
		}
		let entrySize = varint(size, size - position);
		assert(entrySize <= size - position, 'Truncated DAT entry');
		let end = position + entrySize;
		let tag = entryTag(end);
		if (tag != null) {
			file.close();
			printf('%s\n', tag);
			exit(0);
		}
	}
	assert(false, 'No GeoSite or GeoIP tags found in DAT file');
} catch (error) {
	if (file)
		file.close();
	warn(error.message || 'Invalid GeoSite or GeoIP DAT file', '\n');
	exit(1);
}

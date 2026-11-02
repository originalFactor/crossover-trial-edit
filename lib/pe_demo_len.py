#!/usr/bin/env python3
"""Read/patch the CrossOver winewrapper.exe embedded trial length (RT_RCDATA #128).

Usage:
  pe_demo_len.py print  FILE
  pe_demo_len.py set    FILE DAYS
"""
import struct, sys

def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]

class PE:
    def __init__(self, data):
        self.d = data
        e_lfanew = u32(data, 0x3c)
        assert data[e_lfanew:e_lfanew+4] == b'PE\0\0', 'not a PE'
        coff = e_lfanew + 4
        nsec = u16(data, coff + 2)
        optsz = u16(data, coff + 16)
        opt = coff + 20
        magic = u16(data, opt)
        self.pe32plus = (magic == 0x20b)
        ddoff = opt + (112 if self.pe32plus else 96)
        self.rva_rsrc, self.rva_rsrc_size = u32(data, ddoff + 2*8), u32(data, ddoff + 2*8 + 4)
        secoff = opt + optsz
        self.sections = []
        for i in range(nsec):
            o = secoff + i*40
            name = data[o:o+8].rstrip(b'\0').decode('latin1')
            vsize, vaddr, rawsize, rawptr = u32(data, o+8), u32(data, o+12), u32(data, o+16), u32(data, o+20)
            self.sections.append((name, vaddr, vsize, rawptr, rawsize))
    def off(self, rva):
        for name, va, vs, rp, rs in self.sections:
            if va <= rva < va + max(vs, rs):
                return rp + (rva - va)
        raise ValueError('rva 0x%x not mapped' % rva)
    def entries(self, base, rel):
        """yield (id|name, is_name, child_rel) for a resource directory at base+rel"""
        o = base + rel
        n_named, n_id = u16(self.d, o+12), u16(self.d, o+14)
        p = o + 16
        for i in range(n_named + n_id):
            namefield, target = u32(self.d, p + i*8), u32(self.d, p + i*8 + 4)
            is_name = bool(namefield & 0x80000000)
            val = namefield & 0x7fffffff
            yield (val, is_name, target)
    def find(self, want_id=128, want_type=10):
        base = self.off(self.rva_rsrc)
        for tid, is_name, tgt in self.entries(base, 0):
            if is_name or tid != want_type or not (tgt & 0x80000000):
                continue
            for nid, nis_name, ntgt in self.entries(base, tgt & 0x7fffffff):
                if nis_name or nid != want_id or not (ntgt & 0x80000000):
                    continue
                for lid, lis_name, ltgt in self.entries(base, ntgt & 0x7fffffff):
                    if ltgt & 0x80000000:
                        continue
                    o = base + ltgt
                    rva, size = u32(self.d, o), u32(self.d, o+4)
                    return self.off(rva), size
        return None

def main():
    cmd, path = sys.argv[1], sys.argv[2]
    data = bytearray(open(path, 'rb').read())
    pe = PE(bytes(data))
    hit = pe.find()
    if not hit:
        print('RT_RCDATA #128 not found'); return 1
    off, size = hit
    cur = u32(bytes(data), off)
    print('%s: RT_RCDATA#128 file_offset=0x%x size=%d value=%d (0x%x)' % (path, off, size, cur, cur))
    if cmd == 'set':
        days = int(sys.argv[3])
        struct.pack_into('<I', data, off, days)
        open(path, 'wb').write(bytes(data))
        print('patched -> %d days' % days)
    return 0

sys.exit(main())

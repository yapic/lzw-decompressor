# distutils: language=c++
# cython: profile=True
# cython: linetrace=True

cimport cython

cimport libcpp
from libcpp.vector cimport vector
from libcpp.algorithm cimport copy as cppcopy

ctypedef unsigned char uchar
ctypedef vector[uchar] bytestring

cdef class BitReader:
    cdef bytes buf
    cdef unsigned int curr_byte
    cdef unsigned char read_bits
    cdef Py_ssize_t pos
    cdef bytestring mask

    def __cinit__(self, bytes buf):
        self.pos = 0
        self.curr_byte = 0
        self.read_bits = 0
        self.buf = buf
        #self.mask = [0x00, 0x01, 0x03, 0x07, 0x0f, 0x1f, 0x3f, 0x7f]
        self.mask = b'\x00\x01\x03\x07\x0f\x1f\x3f\x7f'

    @cython.boundscheck(False) # turn off bounds-checking for entire function
    @cython.wraparound(False)  # turn off negative index wrapping for entire function
    cpdef int readbits(self, int n):
        cdef int bits_left = n - self.read_bits

        if bits_left > 8:
            if self.pos == len(self.buf):
                print('force EOI')
                return EOI
            self.curr_byte = ((self.curr_byte << 8) | (self.buf[self.pos] & 0xff))
            self.pos += 1
            bits_left -= 8

        self.read_bits = 8 - bits_left
        if self.pos == len(self.buf):
            print('force EOI')
            return EOI
        if self.pos > 64*1024-2:
            print('force EOI')
            return EOI
        cdef unsigned int next_byte = self.buf[self.pos] & 0xff
        self.pos += 1

#        print next_byte, self.read_bits
#        print 'a', (self.curr_byte << bits_left), 'b', (next_byte >> self.read_bits)
        cdef int value = (int (self.curr_byte << bits_left)) | (next_byte >> self.read_bits)
        self.curr_byte = next_byte & self.mask[self.read_bits]
#        print value, n
        return value


cdef unsigned int CLEAR = 256
cdef unsigned int EOI   = 257

cdef tiff_code_len = [9, 12]

cdef bytestring clone1(bytestring v):
    cdef bytestring res = bytestring()
    for i in v:
        res.push_back(i)
    return res


cdef vector[bytestring] clone2(vector[bytestring] v):
    cdef vector[bytestring] res = vector[bytestring]()
    for i in v:
        res.push_back(i)
    return res


cdef vector[bytestring] tiff_table():
    cdef vector[bytestring] table = vector[bytestring]()
    cdef bytestring value = bytestring()

    for i in range(256):
        value.clear()
        value.push_back(i)
        table.push_back(clone1(value))

    value.clear()
    value.push_back(CLEAR)
    table.push_back(clone1(value))

    value.clear()
    value.push_back(EOI)
    table.push_back(clone1(value))

    return table


def tiff_lzw_decompress(bytes buf):
    cdef vector[bytestring] table = tiff_table()
    cdef int a = tiff_code_len[0]
    cdef int b = tiff_code_len[1]
    x = lzw_decompress(table, a, b, buf)
    return x


@cython.boundscheck(False) # turn off bounds-checking for entire function
@cython.wraparound(False)  # turn off negative index wrapping for entire function
cdef bytes lzw_decompress(vector[bytestring] init_table, int min_code_len, int max_code_len, bytes buf):
    cdef int code_len = min_code_len

    cdef vector[bytestring] table
    table = clone2(init_table)

    cdef reader = BitReader(buf)
    
    cdef unsigned int code = 0
    cdef unsigned int old_code = 0
    cdef bytes value = b''
    cdef bytes old_value = b''
    cdef bytes string = b''
    cdef bytes output = b''

    while True:
        code = reader.readbits(code_len)
        
        if code == EOI:
            break
        elif code == CLEAR:
            print('CLEAR', len(buf))
            table.clear()
            table = clone2(init_table)
            code_len = min_code_len

            code = reader.readbits(code_len)
            if code == EOI:
                break

            output += bytes(table[code])
        else:
            if code < table.size():
                #print 1, old_code, code, code_len#, 'c'
                value = bytes(table[code])
                output += value[:]
                assert old_code < table.size()
                table.push_back(bytes(table[old_code]) + value[:1])
            else:
                #print 2, old_code, code, code_len#, 'c'
                old_value = bytes(table[old_code])
                string = old_value[:] + old_value[:1]
                output += string
                table.push_back(string)

        old_code = code
        if table.size() == 511:
            code_len = 10
        elif table.size() == 1023:
            code_len = 11
        elif table.size() == 2047:
            code_len = 12

    print('done')
    return output


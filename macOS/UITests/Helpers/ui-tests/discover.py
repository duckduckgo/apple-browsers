#!/usr/bin/env python3
"""Ask XCTest for its actual test invocations without running setUp or launching the app."""
import ctypes
import json
import os
import re
import sys

ctypes.CDLL(sys.argv[1], mode=os.RTLD_NOW)
objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
ptr = ctypes.c_void_p
objc.objc_getClassList.argtypes = [ptr, ctypes.c_int]
objc.objc_getClassList.restype = ctypes.c_int
objc.class_getName.argtypes = [ptr]
objc.class_getName.restype = ctypes.c_char_p
objc.class_getSuperclass.argtypes = [ptr]
objc.class_getSuperclass.restype = ptr
objc.objc_getClass.argtypes = [ctypes.c_char_p]
objc.objc_getClass.restype = ptr
objc.sel_registerName.argtypes = [ctypes.c_char_p]
objc.sel_registerName.restype = ptr
objc.sel_getName.argtypes = [ptr]
objc.sel_getName.restype = ctypes.c_char_p
objc.class_getClassMethod.argtypes = [ptr, ptr]
objc.class_getClassMethod.restype = ptr
address = ctypes.cast(objc.objc_msgSend, ptr).value
message = ctypes.CFUNCTYPE(ptr, ptr, ptr)(address)
count_message = ctypes.CFUNCTYPE(ctypes.c_ulong, ptr, ptr)(address)
index_message = ctypes.CFUNCTYPE(ptr, ptr, ptr, ctypes.c_ulong)(address)
string_message = ctypes.CFUNCTYPE(ctypes.c_char_p, ptr, ptr)(address)
select = lambda name: objc.sel_registerName(name.encode())
base = objc.objc_getClass(b'XCTestCase')
classes = (ptr * objc.objc_getClassList(None, 0))()
count = objc.objc_getClassList(classes, len(classes))
tests = set()
for klass in list(classes)[:count]:
    name = objc.class_getName(klass).decode()
    if not name.startswith(sys.argv[2] + '.'):
        continue
    parent = klass
    while parent and parent != base:
        parent = objc.class_getSuperclass(parent)
    if not parent:
        continue
    if not objc.class_getClassMethod(klass, select('defaultTestSuite')):
        raise RuntimeError('XCTest has no defaultTestSuite API')
    suite = message(klass, select('defaultTestSuite'))
    cases = message(suite, select('tests'))
    for index in range(count_message(cases, select('count'))):
        case = index_message(cases, select('objectAtIndex:'), index)
        case_name = string_message(message(case, select('name')), select('UTF8String')).decode()
        match = re.fullmatch(r'-\[([^ ]+) (.+)\]', case_name)
        if not match:
            raise RuntimeError('Unexpected XCTest case name: ' + case_name)
        # XCTest normalizes Swift throwing selectors (AndReturnError:) to the test method name.
        tests.add(match[1].rsplit('.', 1)[-1] + '/' + match[2])

if not tests:
    raise RuntimeError('XCTest discovered zero tests')
print(json.dumps(sorted(tests)))

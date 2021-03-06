local lester = require 'nelua.thirdparty.lester'
local describe, it = lester.describe, lester.it

local expect = require 'spec.tools.expect'
local bn = require 'nelua.utils.bn'

local n = bn.parse
local d = bn.fromdec
local h = bn.fromhex
local b = bn.frombin

describe("bn", function()

it("big numbers", function()
  expect.equal('0', n(0):todec())
  expect.equal('0', n(-0):todec())
  expect.equal('1', n(1):todec())
  expect.equal('-1',n(-1):todec())
  expect.equal('0.5', bn.todecsci(0.5))
  expect.equal('-0.5', bn.todecsci(-0.5))
  expect.equal('0.30000000000000004', bn.todecsci(.1+.2))
  expect.equal('1000', bn.todecsci(1000))
  expect.equal('0.14285714285714285', bn.todecsci(n(1)/ n(7)))
  expect.equal('1.4285714285714286', bn.todecsci(n(10)/ n(7)))
  expect.equal('-0.14285714285714285', bn.todecsci(n(-1)/ n(7)))
  expect.equal('-1.4285714285714286', bn.todecsci(n(-10)/ n(7)))
  expect.equal('14.285714285714286', bn.todecsci(n(100)/ n(7)))
  expect.equal('-14.285714285714286', bn.todecsci(n(-100)/ n(7)))
  expect.equal('0.014285714285714287', bn.todecsci(n('0.1')/ n(7)))
  expect.equal('-0.014285714285714287', bn.todecsci(n('-0.1')/ n(7)))
  expect.equal('0.0001', bn.todecsci(0.0001))
  expect.equal('1e-05', bn.todecsci('0.00001'))
  expect.equal('0.0001', bn.todecsci(0.0001))
  expect.equal('1.4285714285714285e-05', bn.todecsci(n(1) / n(70000)))
  expect.equal('1.4285714285714285e-05', bn.todecsci(1 / 70000))
  expect.equal(1, n(1):compress())
  expect.equal(0.5, bn.compress(0.5))
  expect.equal(h'ffffffffffffffff', h'ffffffffffffffff':compress())
end)

it("regular number conversion", function()
  expect.equal(n(0):tonumber(), 0)
  expect.equal(n(1):tonumber(), 1)
  expect.equal(n(-1):tonumber(), -1)
  expect.equal(n(123456789):tonumber(), 123456789)
end)

it("decimal number conversion", function()
  expect.not_fail(function() d'nan' d'inf' d'-inf' end)
  expect.equal(d'0', n(0))
  expect.equal(d'1', n(1))
  expect.equal(d'-1', n(-1))
  expect.equal(d'4096', n(4096))
  expect.equal(d'65536', n(65536))
  expect.equal(bn.todecsci('12345.6789'), '12345.6789')
  expect.equal(bn.todecsci('-12345.6789'), '-12345.6789')

  expect.equal('0', bn.todecsci(0))
  expect.equal('0', bn.todecsci(-0))
  expect.equal('1', bn.todecsci(1))
  expect.equal('-1',bn.todecsci(-1))
  expect.equal('0.5', bn.todecsci(0.5))
  expect.equal('-0.5', bn.todecsci(-0.5))
  expect.equal('0.30000000000000004', bn.todecsci(.1+.2))
  expect.equal('0.30000000000000004', bn.todecsci(n(.1)+n(.2)))
  expect.equal('0.30000000000000004', bn.todecsci(n('.1')+n('.2')))
  expect.equal('1000', bn.todecsci(1000))
end)

it("hexadecimal conversion", function()
  expect.not_fail(function() h'nan' h'inf' h'-inf' end)
  expect.equal(h'0', n(0))
  expect.equal(h'-0', n(0))
  expect.equal(h'1', n(1))
  expect.equal(h'-1', n(-1))
  expect.equal(h'1234567890', n(0x1234567890))
  expect.equal(h'abcdef', n(0xabcdef))
  expect.equal(h'ffff', n(0xffff))
  expect.equal(h'-ffff', n(-0xffff))
  expect.equal(h'ffffffffffffffff', d'18446744073709551615')
  expect.equal(h'-ffffffffffffffff', d'-18446744073709551615')

  expect.equal(h'1234567890abcdef':tohex(), '1234567890abcdef')
  expect.equal(h'0':tohex(), '0')
  expect.equal(h'ffff':tohex(), 'ffff')
  expect.equal(h'-ffff':tohex(64), 'ffffffffffff0001')
end)

it("binary conversion", function()
  expect.not_fail(function() b'nan' b'inf' b'-inf' end)
  expect.equal(b'0', n(0))
  expect.equal(b'1', n(1))
  expect.equal(b'10', n(2))
  expect.equal(b'11', n(3))
  expect.equal(b'-11', n(-3))
  expect.equal(b'11111111', n(255))
  expect.equal(b'100000000', n(256))


  expect.equal(b'11':tobin(), '11')
  expect.equal(b'10':tobin(), '10')
  expect.equal(b'1':tobin(), '1')
  expect.equal(b'0':tobin(), '0')
  expect.equal(h'-1':tobin(8), '11111111')
end)

it("scientific notation", function()
  expect.equal('0.14285714285714285', bn.todecsci(n(1)/ n(7)))
  expect.equal('1.4285714285714286', bn.todecsci(n(10)/ n(7)))
  expect.equal('-0.14285714285714285', bn.todecsci(n(-1)/ n(7)))
  expect.equal('-1.4285714285714286', bn.todecsci(n(-10)/ n(7)))
  expect.equal('14.285714285714286', bn.todecsci(n(100)/ n(7)))
  expect.equal('-14.285714285714286', bn.todecsci(n(-100)/ n(7)))
  expect.equal('0.014285714285714287', bn.todecsci(0.1/ n(7)))
  expect.equal('-0.014285714285714287', bn.todecsci(-0.1/ n(7)))
  expect.equal('0.0001', bn.todecsci(0.0001))
  expect.equal('1e-05', bn.todecsci('0.00001'))
  expect.equal('0.0001', bn.todecsci(0.0001))
  expect.equal('1.4285714285714285e-05', bn.todecsci(n(1) / n(70000)))
  expect.equal('1.4285714285714285e-05', bn.todecsci(1 / 70000))
end)

end)

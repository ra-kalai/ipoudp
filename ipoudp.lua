-- ipoudp.lua
-- Copyright (c) 2016, Ralph Augé
-- All rights reserved.
-- 
-- Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
-- 
-- 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
-- 
-- 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
-- 
-- 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
-- 
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--
--

local cmd = require 'lem.cmd'

local args = {
  last_arg = "[args]+ interface",
  intro = [[
ipoudp -- IP over UDP, is a tool to set up IP tunnel over UDP

basic server usage:
  -s -a 10.8.4.1 -d 10.8.4.2 -p 3999 udpvpn

basic client usage:
  -a 10.8.4.2 -d 10.8.4.1 -e 192.168.1.247 -p 3999 udpvpn

Available options are:
]],
  possible = {
    {'h', 'help', {desc="display this", type='counter'}},
    {'a', 't-addr', {desc="TUN IP Address"}},
    {'d', 't-dst-addr', {desc="TUN destination IP address"}},
    {'n', 't-netmask', {desc="TUN netmask", default_value="255.255.255.255"}},
    {'m', 't-mtu', {desc="TUN device mtu", default_value=1400}},
    {'p', 't-persist', {desc="TUN device persistence 0|1", default_value=1}},
    {'s', 'server', {desc="server mode", type='counter'}},
    {'e', 'external-ip', {desc="external ip, or hostname, or * (0.0.0.0)", default_value='*'}},
    {'p', 'external-port', {desc="external port", default_value=3999}},
    {'u', 'udp-packet-max-size', {desc="udp-packet-max-size", default_value=500}},
    {'l', 'min-packet-loss-resilience', {desc="min resilience to packet-loss in %", default_value=30}},
    {'c', 'collect-interval', {desc="try to send a slice of packet every x second", default_value=0.01}},
    {'t', 'max-delay-for-new-frame', {desc="max timeout in second to consider frame lost", default_value=0.3}},
    {'i', 'info-debug-level', {desc="set info/debug lvl, 1 10 100 1000", default_value=1}},
    {'k', 'keep-alive', {desc="keep alive packet is sent every x second, 0 = never", default_value=0}},
    {'z', 'lz4-compress', {desc="compress packet with lz4 lvl {0..16}, -1 = no", default_value=-1}},
  },
}

local parg = cmd.parse_arg(args, arg)

if parg:is_flag_set('help') or parg.last_arg[0] == nil then
  cmd.display_usage(args, parg)
end

local g_port = tonumber(parg:get_last_val('external-port'))
local g_external_ip = parg:get_last_val('external-ip')

if not parg:is_flag_set('server') then 
  if g_external_ip == '*' then
    io.stderr:write("in client mode specify a valid remote destination: ip or hostname with -e\n")
    os.exit(1)
  end
end

local ltun = require 'ltun'
local io = require 'lem.io'
local utils = require 'lem.utils'
local longhair = require 'longhair'
local lz4 = require 'lz4'

local spawn = utils.spawn
local format = string.format
local utils_sleep = utils.sleep
local utils_now = utils.now

local g_debug_lvl = tonumber(parg:get_last_val('info-debug-level'))
local g_debug_insane_verbose = 1000
local g_debug_very_verbose = 100
local g_debug_verbose = 10
local g_debug_normal = 1

function dbg_p(lvl, raw_or_format, ...)
  if lvl <= g_debug_lvl then
    local now = format("%.4f", utils_now())

    if select('#', ...) == 0 then
      if raw_or_format:find("\n") then
        io.stderr:write(raw_or_format:gsub("([^\n]+\n)",  now ..' > %1'))
      else
        io.stderr:write(now ..' > '..raw_or_format, "\n")
      end
    else
      io.stderr:write(now ..' > '..format(raw_or_format, ...), "\n")
    end
  end
end

local g_udp_packet_max_size = parg:get_last_val('udp-packet-max-size')
local g_min_packet_loss_resilience = tonumber(parg:get_last_val('min-packet-loss-resilience')) / 100.

local g_t_addr = parg:get_last_val('t-addr')
local g_t_dstaddr = parg:get_last_val('t-dst-addr')
local g_t_netmask = parg:get_last_val('t-netmask')
local g_t_mtu = tonumber(parg:get_last_val('t-mtu'))
local g_t_persist = tonumber(parg:get_last_val('t-persistent'))

if g_t_addr == nil or g_t_dstaddr == nil then
  cmd.display_usage(args, parg)
end

dbg_p(g_debug_normal, "creating interface: %s / %s - %s - %s",
  parg.last_arg[0], g_t_addr, g_t_dstaddr, g_t_netmask)

local g_tun = ltun.create(parg.last_arg[0], ltun.IFF_TUN,ltun.IFF_NO_PI)
g_tun.addr = g_t_addr
g_tun.dstaddr = g_t_dstaddr
g_tun.netmask = g_t_netmask
g_tun.mtu = g_t_mtu
g_tun:persist(g_t_persist == 1)
g_tun:up()


local g_tun_stream = io.fromfd(g_tun:fileno())
local g_packet_queue = {}
local g_packet_queue_index = 0
local g_packet_queue_buff_size = 0
local g_last_send_remote = 0
local g_try_send_remote = function () end -- defined by client and server

spawn(function ()
  while true do
    local packet = g_tun_stream:read()
    g_packet_queue_index = g_packet_queue_index + 1
    g_packet_queue[g_packet_queue_index] = packet
    g_packet_queue_buff_size = g_packet_queue_buff_size + #packet
    dbg_p(g_debug_very_verbose,
          'receive tun packet len=%d, packet_queue_buff_size=%d',
          #packet, g_packet_queue_buff_size)
    if g_packet_queue_index > 23 or g_packet_queue_buff_size > 26321 then
      g_try_send_remote()
    end
  end
end)

local g_keep_alive = tonumber(parg:get_last_val('keep-alive'))

if g_keep_alive > 0 then
  spawn(function ()
    local ctime
    while true do
      ctime = utils_now()
      
      if g_last_send_remote + g_keep_alive < ctime then
        if g_packet_queue_index == 0 then
          g_packet_queue[1] = ""
          g_packet_queue_index = 1
          g_try_send_remote()
        end
        utils_sleep(g_keep_alive)
      else
        utils_sleep(g_last_send_remote - ctime + g_keep_alive)
      end
    end
  end)
end


local g_collect_interval = tonumber(parg:get_last_val("collect-interval"))

spawn(function ()
  while true do
    utils_sleep(g_collect_interval)
    g_try_send_remote()
  end
end)

local function gcd(a,b)
  local r
  while b ~= 0 do
    r = a % b
    a = b
    b = r
  end
  return a
end

local function buffer_split_get_size_and_padding(buffer, segment)
  local whole_size = #buffer
  local lcm = 2*(8*segment)/gcd(8,segment)
  local padding = lcm - whole_size % lcm 

  if padding ~= lcm then
    whole_size = whole_size + padding
  else
    padding = 0
  end

  return whole_size, padding
end

--for i=42*8*8,21000 do
--  local s = ('s'):rep(i)
--  wh, padd = buffer_split_get_size_and_padding(s, 42)
--  print(#s, wh, padd, #s%8==0, #s%42==0, (wh/42%8==0), #s/42%8==0)
--end
--os.exit(1)

local function buffer_split(buffer, segment)
  local t = {}
  local whole_size, padding = buffer_split_get_size_and_padding(buffer, segment)

  local s, e
  for i=0,segment-2 do
    s = 1+i*whole_size/segment
    e = (i+1)*whole_size/segment
    t[#t+1] = buffer:sub(s, e)
  end
  
  s = 1+(segment-1)*whole_size/segment
  e = (segment-1+1)*whole_size/segment
  
  if padding ~= 0 then 
    t[#t+1] = buffer:sub(s, e) .. ('\0'):rep(padding)
  else
    t[#t+1] = buffer:sub(s, e)
  end

  return t
end

local g_lz4_compress = tonumber(parg:get_last_val('lz4-compress'))
local math_ceil = math.ceil
local table_concat = table.concat

local g_seq_id = 0

local function hex_dump(buf)
  local t = {}
  for i=1,math_ceil(#buf/16) * 16 do
    if (i-1) % 16 == 0 then t[#t+1] = format('%08X  ', i-1) end
    t[#t+1] =  i > #buf and '   ' or format('%02X ', buf:byte(i))
    if i %  8 == 0 then t[#t+1] = ' ' end
    if i % 16 == 0 then
      t[#t+1] = buf:sub(i-16+1, i):gsub('.', function (c)
        local v = c:byte()
        if v >= 0x20 and v < 0x7f then
          return c
        else
          return '.'
        end
      end)
      t[#t+1] = '\n' end
  end
  return table_concat(t)
end

local function send_bulk(send_method)
  if g_packet_queue_index == 0 then
    return 
  end
  local ctime = utils_now()
  g_last_send_remote = ctime

  local packet_queue_to_proceed = g_packet_queue
  g_packet_queue = {}
  g_packet_queue_index = 0
  g_packet_queue_buff_size = 0


  local bulk_packet = {}

  local index
  local v
  for i=1, #packet_queue_to_proceed do
    index = i * 2
    v = packet_queue_to_proceed[i]

    bulk_packet[index-1] = string.pack(">I2", #v)
    bulk_packet[index] = v
  end

  bulk_packet = table_concat(bulk_packet)

  local is_compressed = 0

  if g_lz4_compress ~= -1 then
    local compressed_bulk_packet = lz4.block_compress_hc(bulk_packet, g_lz4_compress)
    local uncompressed_bulk_packet_len = #bulk_packet
    if #compressed_bulk_packet < uncompressed_bulk_packet_len then
      is_compressed = 0x80
      bulk_packet = table.concat {
        string.pack(">I3I2", uncompressed_bulk_packet_len, #compressed_bulk_packet),
        compressed_bulk_packet }
    end
  end

  local split_count = math_ceil(#bulk_packet / g_udp_packet_max_size)
  local resilience = math_ceil(split_count*g_min_packet_loss_resilience)

  local datagram_to_send
  local chuncksize

  if split_count > 1 then
    local total_size, padding = buffer_split_get_size_and_padding(bulk_packet, split_count)
    chuncksize = total_size / split_count
    datagram_to_send = longhair.cauchy_256_encode(
      split_count, resilience,
      table_concat({ bulk_packet, ('\0'):rep(padding-1) }),
      chuncksize)
  else
    datagram_to_send = buffer_split(bulk_packet, split_count)

    for i=2, resilience do
      datagram_to_send[i] = datagram_to_send[1]
    end
  end


  local seq_id = g_seq_id
  local send_status = 0

  g_seq_id = ( g_seq_id + 1 ) & 0x7f
  seq_id = seq_id | is_compressed

  for i=1, #datagram_to_send do
    send_status = send_method(string.pack(">I1I1I1",seq_id, i, split_count).. datagram_to_send[i])
    -- to test decoding in local
		-- on_datagram(string.pack(">I1I1I1",seq_id, i, split_count).. datagram_to_send[i])
  end


  dbg_p(g_debug_very_verbose,
    'send %d packet in %d udp packet (%3d/%3d) (%db) took: %.4f / seqid->%d / comp=%d',
    #packet_queue_to_proceed, #datagram_to_send, split_count,
    resilience, #bulk_packet, utils.updatenow()-ctime,
    seq_id, seq_id&0x80)

  --dbg_p(g_debug_insane_verbose, hex_dump(bulk_packet))

  return send_status
end

local g_to_inject_queue = {}

local function inject_into_tun(bulk_packet)
  local total_offset = 1
  local pkt_len, off
  local pkt
  local bulk_size = #bulk_packet


  repeat
    pkt_len, off = string.unpack(">I2", bulk_packet, total_offset)

    if pkt_len == 0 or pkt_len-1 + off > bulk_size then
      break
    end


    pkt = bulk_packet:sub(off, off + pkt_len - 1)
    total_offset =  total_offset + 2 + pkt_len

    -- dbg_p(g_debug_insane_verbose, 'pkt offset=%d pkt_len=%d/#=%d', total_offset , pkt_len, #pkt)

    g_tun_stream:write(pkt)
  until total_offset >= bulk_size
end


local g_max_delay_for_new_frame = tonumber(parg:get_last_val('max-delay-for-new-frame'))
local g_last_dec_time = {}

local function on_datagram(datagram)
  local datagram_len = #datagram
  dbg_p(g_debug_very_verbose,'udp receive packet len=%d', datagram_len)

  local dseq_id, dframe_off, split_count = string.unpack(">I1I1I1", datagram)
  local split_extra = math_ceil(split_count*g_min_packet_loss_resilience)

  -- dbg_p(g_debug_insane_verbose, 'bulk-frame last decoding check %03d > %.4f  %d',
  --   dseq_id, g_last_dec_time[dseq_id] or 0, dframe_off)


  if g_last_dec_time[dseq_id] and g_last_dec_time[dseq_id] > utils_now() then
    -- is this redundant datagram for a frame we injected not long time ago ?
    return
  end

  local bulk_packet

  if split_count > 1 then

    if g_to_inject_queue[dseq_id] then

      if g_to_inject_queue[dseq_id].datagram_len ~= datagram_len or
         g_to_inject_queue[dseq_id].off_received[dframe_off] then
        -- if there is an old packet bulk, that we did not decode,
        -- then ignore the old one, and start a new one
        g_to_inject_queue[dseq_id] = nil
      end
    end

    g_to_inject_queue[dseq_id] = g_to_inject_queue[dseq_id] or
      { dec = longhair.cauchy_decoder(split_count,split_extra, datagram_len - 3),
        datagram_len = datagram_len,
        off_received = {}}

    g_to_inject_queue[dseq_id].off_received[dframe_off] = true

    bulk_packet = longhair.cauchy_decoder_push(
      g_to_inject_queue[dseq_id].dec, dframe_off-1,
      datagram:sub(4))


  else
    bulk_packet = datagram:sub(4)
  end

  if bulk_packet then
    g_last_dec_time[dseq_id] = utils_now() + g_max_delay_for_new_frame
    g_to_inject_queue[dseq_id] = nil

    if (dseq_id & 0x80) ==  0x80 then
      -- if compression is enabled
      local decompressed_size, compressed_size, tmp_off = string.unpack(">I3I2", bulk_packet)
      local real_packet_bulk = bulk_packet:sub(tmp_off, tmp_off + compressed_size-1)

      -- dbg_p(g_debug_insane_verbose, table.concat {
      --   format("decomp-size = %4d, compress-size = %4d ,pkt =  \n",
      --         decompressed_size, compressed_size),
      --   hex_dump(bulk_packet)
      -- })

      if decompressed_size < compressed_size then
        -- impossible, data seem corrupt so can only ignore
        return 
      end

      bulk_packet = lz4.block_decompress_safe(real_packet_bulk, decompressed_size)
    end

    dbg_p(g_debug_very_verbose,'parsing bulk-packet %3d len=%d',dseq_id, #bulk_packet)
    inject_into_tun(bulk_packet)
  end
end

if parg:is_flag_set('server') then 
  local sock = io.udp.listen4(g_external_ip, g_port)

  local addr 
  local sock_fd = sock:fileno()
  local send_method

  local ip_port
  sock:autospawn(function (datagram, ip, port)
    on_datagram(datagram)
    local current_ip_port = ip .. ':' .. port
    
    if ip_port ~= current_ip_port  then
			ip_port = current_ip_port

      addr = io.craftaddr(ip, port)
      send_method = function (m) return io.sendto(sock_fd, m, 0, addr) end
      g_try_send_remote = function ()
        send_bulk(send_method)
      end
    end
  end)
else -- client mode
  while true do
    dbg_p(g_debug_normal, "connection to %s:%d", g_external_ip, g_port)
    local sock = io.udp.connect(g_external_ip, g_port)

    if sock then
      local send_method = function (m) return sock:write(m) end

      g_try_send_remote = function ()
        send_bulk(send_method)
      end

      while true do
        local ctime = utils.updatenow()
        local packet = sock:read()

        if packet == nil then
          break
        end

        on_datagram(packet)
      end
    end

    utils_sleep(1)
  end
end

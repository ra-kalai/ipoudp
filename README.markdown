ipoudp
============


About
-----
ipoudp is a command line program, to create IP over UDP tunnel

ipoudp use Cauchy Reed-Solomon Erasure Codes to deal with packet loss,
it provide interesting properties on unreliable links: wireless, Internet with China -> World characteristics.

Performance
-----------

Able to saturate a 100Mbps interface

Opts
----

    usage: ipoudp.lua [args]+ interface
    ipoudp -- IP over UDP, is a tool to set up IP tunnel over UDP
    
    basic server usage:
      -s -a 10.8.4.1 -d 10.8.4.2 -p 3999 udpvpn
    
    basic client usage:
      -a 10.8.4.2 -d 10.8.4.1 -e 192.168.1.247 -p 3999 udpvpn
    
    Available options are:
    
      -h help                                          display this
      -a t-addr                                        TUN IP Address
      -d t-dst-addr                                    TUN destination IP address
      -n t-netmask                   [255.255.255.255] TUN netmask
      -m t-mtu                       [1400]            TUN device mtu
      -p t-persist                   [1]               TUN device persistence 0|1
      -s server                                        server mode
      -e external-ip                 [*]               external ip, or hostname, or * (0.0.0.0)
      -p external-port               [3999]            external port
      -u udp-packet-max-size         [500]             udp-packet-max-size
      -l min-packet-loss-resilience  [30]              min resilience to packet-loss in %
      -c collect-interval            [0.01]            try to send a slice of packet every x second
      -t max-delay-for-new-frame     [0.3]             max timeout in second to consider frame lost
      -i info-debug-level            [1]               set info/debug lvl, 1 10 100 1000
      -k keep-alive                  [0]               keep alive packet is sent every x second, 0 = never
      -z lz4-compress                [-1]              compress packet with lz4 lvl {0..16}, -1 = no

Requirements
------------

  * LEM with Lua 5.3
  * ltun patched for Lua 5.3
  * lua-longhair 
  * lz4 

To Try
-----
    make # should produce an ipoudp binary
    ./ipoudp ...


License
-------

ipoudp is distributed under the terms of a Three clause BSD license or under the [GNU Lesser General Public License][lgpl] any revision.
[lgpl]: http://www.gnu.org/licenses/lgpl.html

Contact
-------

Please send bug reports, patches and feature requests to me ra@apathie.net.

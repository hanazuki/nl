require 'nl'
require 'ynl'
yaml = File.join(__dir__, '../nl-linux/linux/rt_route.yaml')
cls = Ynl::Family.build(yaml)

#p result = cls.open.dump_getaddr(ifa_index: 1)
p result = cls.open.dump_getroute(rtm_family: 1)
binding.irb

#p cls.open.dump_get_stats

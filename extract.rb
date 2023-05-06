#!/usr/bin/ruby -w

if ARGV.length == 0
  puts "usage:"
  puts "  extract.rb <files>"
  exit 1
end

for arg in ARGV
  File.open(arg, "r") do |fd|
    in_code   = false
    in_pyrope = false
    while line = fd.gets
      if line =~ /```/
        in_code = !in_code
        if in_code and (line =~ /```$/ or line =~ /pyrope/)
          in_pyrope = true
          #puts "Another code sample:"
          #puts "```"
        else
          in_pyrope = false
          #puts "```"
          puts
        end
        next
      end

      if in_code and in_pyrope
        unless line =~ /compile error/
          puts line
        end
      end
    end
  end
end


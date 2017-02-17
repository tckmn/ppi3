#!/usr/bin/env ruby

# ppi3 - preprocessor for the i3 window manager
# Copyright (C) 2017  Keyboard Fire <andy@keyboardfire.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

def expand line, expansions, groups
    return line if expansions.empty?

    lines = ''
    pos = Hash.new 0

    loop {

        newline = line.clone
        expansions.reverse.each do |exp|
            newline.insert exp[:pos], exp[:values][pos[exp[:group]] % exp[:values].length]
        end
        lines += newline + ?\n

        idx = 0
        while (pos[groups.keys[idx]] += 1) == groups[groups.keys[idx]]
            pos[groups.keys[idx]] = 0
            idx += 1
            return lines.chomp if idx == groups.keys.length
        end

    }
end

def preprocess config
    global = binding

    # kill comments
    config.gsub! /#+( .*)?\n/, ?\n

    # also annoying leading/trailing/repeated whitespace
    config.gsub! /^\s+|[ \t]+$/, ''
    config.gsub! /[ \t]+/, ' '

    # line continuations
    config.gsub! /\\\n\s*/, ''

    # go through the string matching braces
    nest_positions = []
    pos = 0
    while match = config.match(/([{}])/, pos)
        pos = match.begin(0) + 1
        case match[0]
        when ?{
            nest_positions.push pos
        when ?}
            nest_pos = nest_positions.pop
            if m = config[0...nest_pos].match(/^(group|define) "([^"]+)" {\z/)
                contents = config[m.end(0)...match.begin(0)].strip
                pos = m.begin(0)
                case m[1]
                when 'group'
                    eval "$#{m[2]} = #{contents.inspect}"
                    config[m.begin(0)..match.begin(0)] = contents
                when 'define'
                    eval "$#{m[2]} = #{contents}"
                    config[m.begin(0)..match.begin(0)] = ''
                end
            elsif config[nest_pos-1..nest_pos] == '{{'
                config[nest_pos-1..match.begin(0)] =
                    eval(config[nest_pos+1...match.begin(0)-1]).to_s
                pos = nest_pos
            end
        end
    end

    # now we go through linewise for the *sh-like brace expansions
    config.gsub!(/.+/) {|line|
        expansions = []
        groups = Hash.new 0
        nil while line.sub!(/\{[^}]*\}/) do
            match = $~
            group, values = match[0][1...-1].split ?|, 2
            if values.nil?
                values = group
                group = '__default_group__'
            end
            values = values.split(?,, -1).flat_map{|val|
                val =~ /^(.+)\.\.(.+)$/ ? [*$1..$2] : val
            }
            expansions.push({
                group: group,
                values: values,
                pos: match.begin(0)
            })
            groups[group] = [groups[group], values.length].max
            ''
        end

        expand line, expansions, groups
    }

    # # cleanup: remove empty lines
    # config.gsub! /\n+/, "\n"
    # config.sub! /\A\n/, ''

    config

end

if __FILE__ == $0

    require 'optparse'
    options = {}
    OptionParser.new do |opts|
        opts.banner = 'usage: ppi3 [input-file [output-file]]'
        opts.on('-h', '--help', 'output this help text') do
            puts opts
            exit
        end
        opts.on('-v', '--version', 'output the version of ppi3') do
            puts 'ppi3 version 0.0.1'
            exit
        end
    end.parse!

    infile = STDIN
    outfile = STDOUT
    if infile = ARGV.shift
        infile = infile == '-' ? STDIN : File.open(infile, ?r)
        if outfile = ARGV.shift
            outfile = outfile == '-' ? STDOUT : File.open(outfile, ?w)
        else
            outfile = STDOUT
        end
    else
        infile = STDIN
    end

    outfile.write preprocess infile.read

end

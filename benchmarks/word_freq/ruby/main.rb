# word_freq: counts the words of a file and prints the 20 most frequent.

TOP = 20

text = File.read(ARGV[0])
counts = text.split.tally
ranked = counts.sort_by { |word, count| [-count, word] }

puts "total #{counts.sum { |_, count| count }}"
puts "distinct #{counts.size}"
ranked.first(TOP).each { |word, count| puts "#{count} #{word}" }

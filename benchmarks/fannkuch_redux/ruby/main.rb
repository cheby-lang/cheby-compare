# Fannkuch-redux: flips over every permutation of 0..n, in the order the
# counting algorithm generates them. Prints the alternating checksum and the
# maximum flip count.

# Returns [checksum, max_flips] over all permutations of 0..n, n >= 1.
def fannkuch(n)
  perm1 = (0...n).to_a
  perm = Array.new(n, 0)
  count = Array.new(n, 0)
  max_flips = 0
  checksum = 0
  perm_index = 0
  r = n
  loop do
    while r != 1
      count[r - 1] = r
      r -= 1
    end

    perm.replace(perm1)
    flips = 0
    k = perm[0]
    while k != 0
      # Reverse perm[0..k] in place.
      i = 0
      j = k
      while i < j
        perm[i], perm[j] = perm[j], perm[i]
        i += 1
        j -= 1
      end
      flips += 1
      k = perm[0]
    end
    max_flips = flips if flips > max_flips
    checksum += perm_index.even? ? flips : -flips

    loop do
      return [checksum, max_flips] if r == n

      # Rotate perm1[0..r] left by one.
      first = perm1[0]
      i = 0
      while i < r
        perm1[i] = perm1[i + 1]
        i += 1
      end
      perm1[r] = first
      count[r] -= 1
      break if count[r] > 0

      r += 1
    end
    perm_index += 1
  end
end

n = Integer(ARGV[0])
checksum, max_flips = fannkuch([n, 1].max)
puts checksum
puts "Pfannkuchen(#{n}) = #{max_flips}"

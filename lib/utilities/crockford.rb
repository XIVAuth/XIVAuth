# Sourced from https://github.com/iain/crockford, under MIT license.
# Encodes and decodes Crockford's Base32 variation.
module Crockford
  ENCODER = %w[0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K M N P Q R S T V W X Y Z].freeze
  DECODER = ENCODER.each_with_index.to_h.transform_keys(&:to_s).merge({ "I" => 1, "L" => 1, "O" => 0 }).freeze

  class << self
    def encode_number(number, **)
      string = number.to_s(2).each_char.reverse_each.each_slice(5).map do |bits|
        ENCODER[bits.reverse.join.to_i(2)]
      end.reverse.join

      format_code(string, **)
    end

    def decode_number(string)
      clean_code(string).each_char.inject(0) do |result, char|
        val = DECODER[char]
        return nil if val.nil?

        (result << 5) + val
      end
    end

    def encode_string(string, **)
      number = string.bytes.map { |byte| format("%08b", byte) }.join.to_i(2)
      encode_number(number, **)
    end

    def decode_string(string)
      number = decode_number(string)
      return nil if number.nil?

      number.to_s(2).each_char.reverse_each.each_slice(8).map do |byte|
        byte.reverse.join.to_i(2)
      end.reverse.pack("C*")
    end

    def normalize(string, unknown: "?", **)
      string = clean_code(string).each_char.inject("") do |memo, char|
        memo + ((index = DECODER[char]) ? ENCODER[index] : unknown)
      end
      format_code(string, **)
    end

    def valid?(string)
      !decode_number(string).nil?
    end

    def generate(length: 16, split: false)
      encode_number(SecureRandom.random_number(32 ** length), split: split, length: length)
    end

    private def clean_code(string)
      string.delete("-").upcase
    end

    private def format_code(string, length: nil, split: false)
      string = string.rjust(length, "0") if length

      if split
        string = string
                 .each_char
                 .reverse_each
                 .each_slice(split)
                 .map { |segment| segment.reverse.join }
                 .reverse
                 .join("-")
      end

      string
    end
  end
end

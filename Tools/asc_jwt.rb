#!/usr/bin/env ruby
require 'json'
require 'base64'

key_file = ENV['ASC_KEY_FILE'] || File.join(ENV.fetch('RUNNER_TEMP', ''), 'asc-api-key.p8')
%w[ASC_KEY_ID ASC_ISSUER_ID].each do |name|
  abort "ERROR: #{name} is not set" if ENV[name].to_s.empty?
end
abort "ERROR: API key file is missing" unless File.file?(key_file)

def b64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

now = Time.now.to_i
header = b64url(JSON.generate('alg' => 'ES256', 'kid' => ENV.fetch('ASC_KEY_ID'), 'typ' => 'JWT'))
payload = b64url(JSON.generate('aud' => 'appstoreconnect-v1', 'iss' => ENV.fetch('ASC_ISSUER_ID'),
                               'iat' => now, 'exp' => now + 600))
signing_input = "#{header}.#{payload}"
der = IO.popen(['openssl', 'dgst', '-sha256', '-sign', key_file], 'r+b') do |io|
  io.write(signing_input)
  io.close_write
  io.read
end
abort 'ERROR: OpenSSL signing failed' if der.nil? || der.empty?

def der_int(der, offset)
  raise 'malformed ECDSA signature' unless der.getbyte(offset) == 0x02
  length = der.getbyte(offset + 1)
  body = der.byteslice(offset + 2, length)
  body = body[1..] if body.getbyte(0) == 0
  [body.rjust(32, "\x00".b), offset + 2 + length]
end

offset = 2
r, offset = der_int(der, offset)
s, = der_int(der, offset)
warn 'ASC JWT created; API key values are not logged.'
print "#{signing_input}.#{b64url((r + s).b)}"

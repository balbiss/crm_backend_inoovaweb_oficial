require 'net/http'
require 'json'
res = Net::HTTP.get(URI('http://baileys-api:3025/documentation/json'))
File.write('docs.json', res)
docs = JSON.parse(res)
puts docs['paths'].keys.grep(/download/)

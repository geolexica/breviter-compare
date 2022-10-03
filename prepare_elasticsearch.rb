# frozen_string_literal: true

# gem install elasticsearch -v 7.10.1

require 'bundler/setup'
require 'elasticsearch'
require 'typhoeus'
require 'json'

client = Elasticsearch::Client.new(
  adapter: :typhoeus,
  log: true
)

client.cluster.health

SETTINGS = {
  settings: {
    index: {
      number_of_shards: 1,
      number_of_replicas: 0
    }
  }
}.freeze

# Create index
client.indices.create(index: 'semantic_development', body: SETTINGS)

MAPPINGS = {
  dynamic: 'strict',
  _source: { enabled: 'true' },

  properties: {
    id: {
      type: 'keyword'
    },
    term: {
      type: 'text'
    },
    definition: {
      type: 'text'
    },
    vector: {
      type: 'dense_vector',
      dims: 512
    }
  }
}.freeze

# Define mappings for index
client.indices.put_mapping(index: 'semantic_development', body: MAPPINGS)

# Verify that the index is created
client.indices.get(index: 'semantic_development')

db_json = File.read('db.json')
db = JSON.parse(db_json)

puts 'Indexing Terms ...'
db.each do |term|
  client.index(id: term['id'], index: 'semantic_development', body: term)
end
puts 'Indexing Done'

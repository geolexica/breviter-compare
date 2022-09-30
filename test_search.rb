# frozen_string_literal: truet

require "elasticsearch"
require "typhoeus"
require "json"
require "yaml"

data = File.read("test-vectors.txt")
test_cases = JSON.parse(data)

client = Elasticsearch::Client.new(
  adapter: :typhoeus,
  log: true
)

def search(client, query)
  client.search(
    index: "semantic_development",
    body: {
      "size": 10,
      "query": query,
      "_source": { "includes": ["term"] }
    }
  )
end

def calculate_rank(response, expected_result)
  response["hits"]["hits"].index do |hit|
    hit["_source"]["term"] == expected_result
  end
end

results = []

test_cases.each do |test_case|
  query = test_case[0]
  expected_result = test_case[1]
  vector = test_case[2]

  script_query = {
    "script_score": {
      "query": { "match_all": {} },
      "script": {
        "source": "cosineSimilarity(params.query_vector, 'vector') + 1.0",
        "params": { "query_vector": vector }
      }
    }
  }

  response = search(client, script_query)
  rank = calculate_rank(response, expected_result)

  results << {
    query: query,
    expected_result: expected_result,
    rank: rank || -1
  }
end

File.open("test_results.yml", "w") do |f|
  f.puts(results.to_yaml)
end

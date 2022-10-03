# frozen_string_literal: true

require 'bundler/setup'
require 'elasticsearch'
require 'typhoeus'
require 'json'
require 'yaml'

def run_tests(client, test_cases)
  results = []
  test_cases.each do |test_case|
    query = test_case[0]
    expected_result = test_case[1]
    vector = test_case[2]

    keyword_script_query = {
      "match": {
        "definition": query
      }
    }

    script_query = {
      "script_score": {
        "query": { "match_all": {} },
        "script": {
          "source": "cosineSimilarity(params.query_vector, 'vector') + 1.0",
          "params": { "query_vector": vector }
        }
      }
    }

    rank = calculate_rank_from_query(client: client, script_query: script_query, expected_result: expected_result)
    keyword_rank = calculate_rank_from_query(client: client, script_query: keyword_script_query,
                                             expected_result: expected_result)

    results << {
      query: query,
      expected_result: expected_result,
      rank: rank || -1,
      keyword_rank: keyword_rank || -1
    }
  end

  results
end

def search(client, query)
  client.search(
    index: 'semantic_development',
    body: {
      "size": 10,
      "query": query,
      "_source": { "includes": ['term'] }
    }
  )
end

def calculate_rank(response, expected_result)
  response['hits']['hits'].index do |hit|
    hit['_source']['term'] == expected_result
  end
end

def calculate_rank_from_query(client:, script_query:, expected_result:)
  response = search(client, script_query)
  calculate_rank(response, expected_result)
end

def main
  client = Elasticsearch::Client.new(
    adapter: :typhoeus,
    log: true
  )

  data = File.read('test-vectors.txt')
  test_cases = JSON.parse(data)
  results = run_tests(client, test_cases)

  File.open('test_results_es.yml', 'w') do |f|
    f.puts(results.to_yaml)
  end

  puts(results.to_yaml)
end

main

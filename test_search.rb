# frozen_string_literal: true

require 'bundler/setup'
require 'elasticsearch'
require 'typhoeus'
require 'json'
require 'yaml'

RANK_NOT_FOUND = 200
FIT_SCORES = {
  1 => 20,
  3 => 10,
  5 => 5,
  10 => 3,
  20 => 1,
  RANK_NOT_FOUND => -3 # Bucket for no matches in top 20
}.freeze

LENS = FIT_SCORES.keys.freeze

#
# Rank 1      => 1st partition
# Rank 2-3    => 2nd partition
# Rank 4-5    => 3rd partition
# Rank 6-10   => 4th partition
# Rank 11-20  => 5th partition
# Rank 21-200 => 6th partition
# Default rank partition is the last one.
#
# It is used for calculating fit score.
#
def get_rank_partition(rank)
  default_rank_partition = LENS[LENS.length - 1]
  return default_rank_partition if rank.nil? || rank.negative?

  LENS.find { |partition| rank < partition } || default_rank_partition
end

def get_score_from_rank(rank)
  FIT_SCORES[get_rank_partition(rank)]
end

def add_fit_scores(results)
  result_size = results.length
  max_individual_score = FIT_SCORES.values.max
  max_overall_score = result_size * max_individual_score
  fit_scores = results
               .map do |result_entry|
    {
      query: result_entry[:query],
      expected_result: result_entry[:expected_result],
      fit_score__rs: get_score_from_rank(result_entry[:rank__rs]),
      fit_score__keyword: get_score_from_rank(result_entry[:rank__keyword]),
    }
  end

  overall_fit_score__rs = fit_scores
                          .reduce(0) { |acc, result_entry| acc + result_entry[:fit_score__rs] }.to_f / max_overall_score

  overall_fit_score__keyword = fit_scores
                               .reduce(0) { |acc, result_entry| acc + result_entry[:fit_score__keyword] }.to_f / max_overall_score

  {
    results: results,
    overall_fit_score__rs: overall_fit_score__rs,
    overall_fit_score__keyword: overall_fit_score__keyword,
    fit_scores: fit_scores
  }
end

def display_overall_fit_score_formula(results)
  result_size = results.length
  max_individual_score = FIT_SCORES.values[0]
  max_overall_score = result_size * max_individual_score

  rank_partitions__rs = results.map do |result_entry|
    get_rank_partition(result_entry[:rank__rs])
  end

  rank_partitions__keyword = results.map do |result_entry|
    get_rank_partition(result_entry[:rank__keyword])
  end

  overall_score__rs = rank_partitions__rs.reduce(0) do |acc, rank_partition|
    acc + FIT_SCORES[rank_partition]
  end

  overall_score__keyword = rank_partitions__keyword.reduce(0) do |acc, rank_partition|
    acc + FIT_SCORES[rank_partition]
  end

  sorted_by_rank_partitions__rs = rank_partitions__rs.each_with_object({}) do |partition, acc|
    acc[partition] ||= 0
    acc[partition] += 1
  end

  sorted_by_rank_partitions__keyword = rank_partitions__keyword.each_with_object({}) do |partition, acc|
    acc[partition] ||= 0
    acc[partition] += 1
  end

  {
    mult: {
      rs: display_formula(sorted_by_rank_partitions__rs, max_overall_score, overall_score__rs, '×').to_s,
      keyword: display_formula(sorted_by_rank_partitions__keyword, max_overall_score, overall_score__keyword, '×').to_s
    },
    '*': {
      rs: display_formula(sorted_by_rank_partitions__rs, max_overall_score, overall_score__rs).to_s,
      keyword: display_formula(sorted_by_rank_partitions__keyword, max_overall_score, overall_score__keyword).to_s
    }
  }
end

def display_formula(sorted_by_rank_partitions, denominator, overall_score, mult = '*')
  "(#{
    sorted_by_rank_partitions.keys
                             .sort_by { |partition| -FIT_SCORES[partition.to_i] }
                             .map { |partition| "#{FIT_SCORES[partition.to_i]}#{mult}#{sorted_by_rank_partitions[partition.to_i]}" }
                             .join(' + ')})" \
    " / #{denominator}" \
    " = #{overall_score.to_f / denominator}"
end

def run_tests(client, test_cases)
  test_cases.map do |test_case|
    query = test_case[0]
    expected_result = test_case[1]
    vector = test_case[2]

    script_query__keyword = {
      "match": {
        "definition": query
      },
    }

    script_query__rs = {
      "script_score": {
        "query": { "match_all": {} },
        "script": {
          "source": "cosineSimilarity(params.query_vector, 'vector') + 1.0",
          "params": { "query_vector": vector }
        },
      },
    }
    response__rs = search(client, script_query__rs)
    response__keyword = search(client, script_query__keyword)

    rank__rs = calculate_rank_from_response(
      response: response__rs,
      expected_result: expected_result
    )

    rank__keyword = calculate_rank_from_response(
      response: response__keyword,
      expected_result: expected_result
    )

    {
      query: query,
      expected_result: expected_result,
      rank__rs: rank__rs || RANK_NOT_FOUND,
      rank__keyword: rank__keyword || RANK_NOT_FOUND
    }
  end
end

def search(client, query)
  client.search(
    index: 'semantic_development',
    body: {
      "size": 20,
      "query": query,
      "_source": { "includes": [:term] }
    }
  )
end

def calculate_rank_from_response(response:, expected_result:)
  response['hits']['hits'].index do |hit|
    hit['_source']['term'] == expected_result
  end
end

def main
  client = Elasticsearch::Client.new(
    adapter: :typhoeus,
    log: true
  )

  data = File.read('test-vectors.txt')
  test_cases = JSON.parse(data)
  results = run_tests(client, test_cases)

  results_with_fit_score_formulas = display_overall_fit_score_formula(results)
  results_with_fit_scores = add_fit_scores(results)
  results_with_fit_scores[:fit_scores] = results_with_fit_score_formulas

  File.open('test_results_es.yml', 'w') do |f|
    f.puts(results_with_fit_scores.to_yaml)
  end

  puts(results_with_fit_scores.to_yaml)
end

main

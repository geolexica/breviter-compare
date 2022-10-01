.PHONY: all test_search setup_docker setup_elasticsearch install_elasticsearch

all: install_elasticsearch test_search

test_search: test-vectors.txt
	ruby test_search.rb

test-vectors.txt:
	node prepare-test-vectors.js test_case.txt

setup_docker:
	docker network create elastic-network
	docker run -d --name elasticsearch --net elastic-network \
		-p 9200:9200 -p 9300:9300 \
		-e "discovery.type=single-node" \
		-e "xpack.security.enabled=false" \
		elasticsearch:8.4.2

kill_docker:
	docker rm -f $$(docker ps -f name=elasticsearch -q)
	docker network prune -f

install_elasticsearch:
	bundle install

setup_elasticsearch:
	ruby prepare-elasticsearch.rb

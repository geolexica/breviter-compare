.PHONY: all test_search setup_docker setup_elasticsearch prerequisites

all: prerequisites test_search

test_search_google: test-vectors-google.txt
	cp test-vectors-google.txt test-vectors.txt
	ruby test_search.rb

test_search_iso: test-vectors-iso.txt
	cp test-vectors-iso.txt test-vectors.txt; \
	ruby test_search.rb

test-vectors-iso.txt:
	node prepare-test-vectors.js tests/dataset-iso.csv; \
	mv test-vectors.txt $@

test-vectors-google.txt:
	node prepare-test-vectors.js tests/dataset-google.csv; \
	mv test-vectors.txt $@

setup_docker:
	docker network create elastic-network
	docker run -d --name elasticsearch --net elastic-network \
		-p 9200:9200 -p 9300:9300 \
		-e "discovery.type=single-node" \
		-e "xpack.security.enabled=false" \
		elasticsearch:8.4.2

kill_docker:
	CONTAINER=$$(docker ps -f name=elasticsearch -q -a); \
	[ -z "$$CONTAINER" ] || docker rm -f $$CONTAINER; \
	docker network prune -f

prerequisites: | update
	bundle install
	yarn
	cd breviter && yarn

setup_elasticsearch: db.json | prerequisites
	ruby prepare_elasticsearch.rb

db.json: | prerequisites
	cd breviter && yarn compute
	cp breviter/public/db.json db.json

clean: kill_docker
	rm -f test-vectors.txt

setup: setup_docker setup_elasticsearch

update:
	git submodule update --init --recursive

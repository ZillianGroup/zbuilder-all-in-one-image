.PHONY: build all run-test run-non-root-test rm-test

all: build 

build:
	docker build ./ -f ./Dockerfile -t zweb-builder:local

run-test:
	docker run -d -p 80:2022 --name zweb_builder_local -v ~/zweb-database:/opt/zweb/database -v ~/zweb-drive:/opt/zweb/drive zweb-builder:local

run-non-root-test:
	docker run -d -p 80:2022 --name zweb_builder_local --user 1002:1002 -v ~/zweb-database:/opt/zweb/database -v ~/zweb-drive:/opt/zweb/drive zweb-builder:local

rm-test:
	docker stop zweb_builder_local; docker rm zweb_builder_local;

 	

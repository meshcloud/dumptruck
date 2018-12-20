.PHONY: build release

VERSION=1.1

build:
	docker build . -t meshcloud/dumptruck

release: build
	git tag $(VERSION)
	docker tag meshcloud/dumptruck meshcloud/dumptruck:$(VERSION)
	docker push meshcloud/dumptruck 
	docker push meshcloud/dumptruck:$(VERSION)
# Basics
PROJECT_NAME 		:= ysc

DOCKER_DIR 		?= etc/docker
DOCKER_COMPOSE_FILE	?= $(DOCKER_DIR)/docker-compose.yml
RELEASE_DOCKERFILE 	?= $(DOCKER_DIR)/Dockerfile

# Versioning
VERSION_LONG 		 = $(shell git describe --first-parent --abbrev=10 --long --tags --dirty)
VERSION_SHORT 		 = $(shell echo $(VERSION_LONG) | cut -f 1 -d "-")
DATE_STRING 		 = $(shell date +'%m-%d-%Y')
GIT_HASH  		 = $(shell git rev-parse --verify HEAD)

##
# ~~~ Dev Targets ~~~
##

# Dummy variables needed for local dev server
export AWS_ACCESS_KEY_ID="fake"
export AWS_SECRET_ACCESS_KEY="secret"

dev:  ## Start the local dev server
	@mix phx.server

dev-setup:  ## Set up local dev environment
	@mix deps.get
	@docker-compose -f $(DOCKER_COMPOSE_FILE) up -d
	PGPASSWORD="postgres" DBNAME="ysc_dev" ./etc/scripts/_wait_db_connection.sh
	@ if [ "$($(reset-db))" = "true" ]; then $(MAKE) reset-db; fi
	$(MAKE) setup-dev-db
	@awslocal s3api create-bucket --bucket media || true
	@awslocal s3api put-bucket-cors --bucket media --cors-configuration file://etc/config/s3_bucket_cors_rules.json || true
	@echo " "
	@echo "$(GREEN)Your local dev env is ready!$(RESET)"
	@echo "Run $(BOLD)make dev$(RESET) to start the server and then visit $(BOLD)http://localhost:4000/$(RESET)"

reset-db:  ## Drop the local dev db
	@mix ecto.drop

setup-dev-db:  ## Create, migrate and seed the local dev database
	@mix ecto.create
	@mix ecto.migrate
	@mix run priv/repo/seeds.exs || true

test:  ## Run the test suite
	@mix test

tests: test

clean-compose:
	@docker-compose -f $(DOCKER_COMPOSE_FILE) down -v --remove-orphans

clean-docker: clean-compose  ## Delete docker images, volumes and networks
	@echo "$(BOLD)** Cleaning up Docker resources...$(RESET)"
	docker-compose -f $(DOCKER_COMPOSE_FILE) rm

clean-elixir:  ## Clean up Elixir and Phoenix files
	@echo "$(BOLD)** Cleaning up Elixir files...$(RESET)"
	mix clean
	rm -rf _build/ deps/

clean: clean-elixir clean-docker  ## Clean docker and elixir

##
# ~~~ Release Targets ~~~
##

version:  ## Print the current version
	@echo $(VERSION_LONG)

release:  ## Build and tag a docker image for release
	@docker -f $(RELEASE_DOCKERFILE) build $(PROJECT_NAME):$(VERSION_LONG) .
	@docker tag $(PROJECT_NAME):$(VERSION_LONG) $(PROJECT_NAME):$(VERSION_SHORT)
	@docker tag $(PROJECT_NAME):$(VERSION_LONG) $(PROJECT_NAME):latest

##
# ~~~ Make Helpers ~~~
##

# Formatting variables
BOLD 			:= $(shell tput bold)
RESET 			:= $(shell tput sgr0)
RED 			:= $(shell tput setaf 1)
GREEN 			:= $(shell tput setaf 2)
TEAL 			:= $(shell tput setaf 6)

.DEFAULT_GOAL := help

.PHONY: dev dev-setup reset-db setup-dev-db test tests clean-compose \
	clean-docker clean-elixir clean version release help

help:  ## Print this make target help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make $(TEAL)<target>$(RESET)\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n$(TEAL)%s$(RESET)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@printf "\n"

arg-%: ARG  # Checks if param is present: make key=value
	@ if [ "$($(*))" = "" ]; then echo "$(RED)Missing param: $(BOLD)$(*)$(RESET)$(RED). Use '$(BOLD)make $(MAKECMDGOALS) $(*)=value$(RESET)$(RED)'$(RESET)" && exit 1; fi

guard-%: GUARD
	@ if [ -z "${${*}}" ]; then echo "$(RED)Required environment variable $(BOLD)$*$(RESET)$(RED) not set.$(RESET)" && exit 1; fi

# This crap protects against files named the same as the target
.PHONY: GUARD
GUARD:

.PHONY: ARG
ARG:

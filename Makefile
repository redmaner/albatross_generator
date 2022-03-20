clean:
	mix clean --deps

tests:
	MIX_ENV=test mix test --no-start

dev:
	mix deps.get 
	MIX_ENV=dev mix deps.compile 
	MIX_ENV=dev mix compile 

run-dev:
	touch ./albagen.sqlite	
	SQLITE_PATH=./albagen.sqlite elixir --cookie albagen --name albagen@`hostname -i` -S mix run --no-halt

release:
	mix deps.get --only-prod
	mix_ENV=prod mix deps.compile
	MIX_ENV=prod mix release 

run-release:
	SQLITE_PATH=./albagen.sqlite _build/prod/rel/albagen/bin/albagen start

docker-image:
	docker buildx build -t albagen:latest .

docker-compose-up:
	docker-compose -f ./docker-compose.yaml up -d 

docker-compose-down:
	docker-compose -f ./docker-compose.yaml down 

docker-compose-log:
	docker-compose -f ./docker-compose.yaml logs -f
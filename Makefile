.PHONY: $(MAKECMDGOALS)

APP_NAME="MYAPP"
NETWORK_NAME=${APP_NAME}-network

create-network:
	podman network create ${NETWORK_NAME} 2>/dev/null || true

# Stop the database container
stop-oracle-database:
	podman stop -i $(APP_NAME)-oracle-database
	podman rm -i $(APP_NAME)-oracle-database

# Start a database container
start-oracle-database: stop-database create-network
	podman run --name $(APP_NAME)-oracle-database --network=${NETWORK_NAME} -d -p 1521:1521 -p 5500:5500 \
		-e ORACLE_PWD=strongPass \
		-v ./environment/oracle/startup/:/docker-entrypoint-initdb.d/startup/ \
		database/express:21.3.0-xe

# Stop the database container
stop-postgres-database:
	podman kill $(APP_NAME)-postgres || true
	podman rm $(APP_NAME)-postgres || true

# Start a database container
start-postgres-database: stop-postgres-database create-network
	podman run --name $(APP_NAME)-postgres \
		--network=${NETWORK_NAME} \
		-e POSTGRES_PASSWORD=strongPass -p 5432:5432 \
		docker.io/library/postgres

# Stop the Prometheus instance
stop-prometheus:
	podman stop -i $(APP_NAME)-prometheus
	podman rm -i $(APP_NAME)-prometheus

# Start a Prometheus instance with the classpath yaml config
start-prometheus: stop-prometheus create-network
	podman run --name $(APP_NAME)-prometheus --network=${NETWORK_NAME} -d -p 9090:9090 \
		-v ./environment/prometheus/prometheus.yaml:/etc/prometheus/prometheus.yml \
		prometheus:latest

# Stop the Grafana instance
stop-grafana:
	podman stop -i $(APP_NAME)-grafana
	podman rm -i $(APP_NAME)-grafana

# Start the Grafana instance
start-grafana: stop-grafana create-network
	podman run --name $(APP_NAME)-grafana --network=${NETWORK_NAME} -d -p 3000:3000 \
		-v ./environment/grafana/provisioning/:/etc/grafana/provisioning/ \
		-e GF_AUTH_ANONYMOUS_ENABLED=true \
		-e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
		-e GF_SERVER_DOMAIN=localhost \
		grafana/grafana:8.5.5

# Stop Prometheus and Grafana
stop-monitoring: stop-grafana stop-prometheus

# Start Prometheus and grafana
start-monitoring: stop-monitoring start-prometheus start-grafana


# Stop the RabbitMQ broker
stop-rabbit:
	podman stop -i $(APP_NAME)-rabbit
	podman rm -i $(APP_NAME)-rabbit

# Start the RabbitMQ broker
start-rabbit: stop-rabbit create-network
	podman run -d --rm --name $(APP_NAME)-rabbit --network=${NETWORK_NAME} \
		-p 5672:5672 -p 15672:15672 -p 15692:15692 \
		-e RABBITMQ_DEFAULT_USER=tester \
		-e RABBITMQ_DEFAULT_PASS=strongPass \
		-v ./environment/rabbitmq/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf \
		-v ./environment/rabbitmq/definitions.json:/etc/rabbitmq/definitions.json:ro \
		rabbitmq:3-management

# Start Kafka environment.
start-kafka: stop-kafka create-network
	podman run -d \
		--name ${APP_NAME}-zookeeper \
		--network=${NETWORK_NAME} \
		-e ZOOKEEPER_CLIENT_PORT=2181 \
		-e ZOOKEEPER_TICK_TIME=2000 \
		confluentinc/cp-zookeeper:latest
	podman run -d \
		--name ${APP_NAME}-kafka \
		-p 29092:29092 \
		--network=${NETWORK_NAME} \
		-e KAFKA_BROKER_ID=1 \
		-e KAFKA_ZOOKEEPER_CONNECT=${APP_NAME}-zookeeper:2181 \
		-e KAFKA_ADVERTISED_LISTENERS=LISTENER_CONTAINER://${APP_NAME}-kafka:9092,LISTENER_HOST://localhost:29092 \
		-e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=LISTENER_CONTAINER:PLAINTEXT,LISTENER_HOST:PLAINTEXT \
		-e KAFKA_INTER_BROKER_LISTENER_NAME=LISTENER_CONTAINER \
		-e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
		confluentinc/cp-kafka:latest
	podman run -d \
		--name ${APP_NAME}-kafka-ui \
		--network=${NETWORK_NAME} \
		-p 8081:8080 \
		-e DYNAMIC_CONFIG_ENABLED=true \
		provectuslabs/kafka-ui:master

# Stop Kafka environment.
stop-kafka:
	podman stop -i ${APP_NAME}-kafka-ui
	podman rm -i ${APP_NAME}-kafka-ui
	podman stop -i ${APP_NAME}-kafka
	podman rm -i ${APP_NAME}-kafka
	podman stop -i ${APP_NAME}-zookeeper
	podman rm -i ${APP_NAME}-zookeeper
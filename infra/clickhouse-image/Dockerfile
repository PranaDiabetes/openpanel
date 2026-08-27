FROM clickhouse/clickhouse-server:25.10.2.65

COPY docker/clickhouse/clickhouse-config.xml /etc/clickhouse-server/config.d/op-config.xml
COPY docker/clickhouse/clickhouse-user-config.xml /etc/clickhouse-server/users.d/op-user-config.xml
COPY docker/clickhouse/init-db.sh /docker-entrypoint-initdb.d/init-db.sh

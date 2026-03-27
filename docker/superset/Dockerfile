FROM apache/superset:3.1.0

USER root
RUN pip install clickhouse-connect

COPY superset_config.py /app/pythonpath/superset_config.py

COPY docker-init.sh /docker-init.sh
RUN chmod +x /docker-init.sh

USER superset
ENTRYPOINT ["/docker-init.sh"]

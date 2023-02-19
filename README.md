# [ WIP ]

## Schema

**request_method** *[required]*
- Métodos HTTP que serão eleitos ao cache
    - default: GET, HEAD
    - permitido: HEAD, GET, POST, PATCH, PUT

**response_code** *[required]*
- Status code HTTP que serão eleitos ao cache
    - default: 200, 301, 404

**content_type** *[required]*
- Content type que serão eleitos ao cache
    - default: text/plain, application/json

**cache_ttl** *[required]*
- Tempo em segundos que o cache será armazenado, quando `cache_ttl=0` não haverá expiração
    - permitido: memory, redis

**strategy** *[required]*
- Estratégia de armazenamento que será utilizada
    - permitido: memory, redis

**key_mapper**
- Possibilita configurar elementos da request (path/query param, header e etc) para ser utilizado como key do redis, portanto só deve ser declarado quando `strategy=redis`.
    - permitido: No momento só é possível utilizar `path param`, pois os outros elementos estão em desenvolvimento

**redis**
- Configuração do Redis a ser utilizado como storage, portanto só deve ser declarado quando `strategy=redis`.

**memory**
- Configuração para uso do storage em memória, portanto só deve ser declarado quando `strategy=memory`.

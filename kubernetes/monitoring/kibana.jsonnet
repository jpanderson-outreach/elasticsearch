local ok = import 'kubernetes/outreach.libsonnet';
local cluster = ok.cluster;
local host = 'kibana.%s.%s.outreach.cloud' % [cluster.environment, cluster.region];

local all(name, namespace) = {
  deployment: ok.Deployment(name, namespace) {
    spec+: {
      replicas: 3,
      strategy: {
        type: 'RollingUpdate',
        rollingUpdate: {
          maxSurge: '50%',
          maxUnavailable: 1,
        },
      },
      template+: {
        spec+: {
          containers+: [
            ok.Container('oauth2-proxy'){
              image: 'registry.outreach.cloud/oauth2_proxy:2.2.1-alpha.outreach-1.0.7',
              args: [
                '-upstream=http://localhost:5601/',
                '-provider=okta',
                '-cookie-name=_%s_kibana_proxy' % [cluster.name],
                '-cookie-secure=true',
                '-cookie-expire=168h0m',
                '-cookie-refresh=8h',
                '-cookie-domain=' + host,
                '-http-address=0.0.0.0:8080',
                '-okta-domain=outreach.okta.com',
                '-redirect-url=https://%s/oauth2/callback' % [host],
                '-email-domain=outreach.io',
              ],
              envFrom: [
                { secretRef: { name: 'kibana-oauth-proxy'} },
              ],
              ports: [
                { containerPort: 8080, name: 'oauth-proxy' },
              ],
              resources: {
                limits: {
                  memory: '100Mi',
                },
                requests: {
                  cpu: '10m',
                },
              },
            },
            ok.Container(name){
              image: 'docker.elastic.co/kibana/kibana-oss:6.6.1',
              env: [
                { name: 'SERVER_NAME', value: host },
                { name: 'ELASTICSEARCH_REQUESTTIMEOUT', value: '600000' },
                { name: 'ELASTICSEARCH_URL', value: 'http://elasticsearch-logging:9200' },
                { name: 'MAP_INCLUDEELASTICMAPSSERVICE', value: 'false' },
              ],
              livenessProbe: {
                tcpSocket: { port: 'kibana' },
                initialDelaySeconds: 30,
                periodSeconds: 10,
              },
              readinessProbe: {
                httpGet: {
                  path: '/app/kibana',
                  port: 'kibana',
                },
                initialDelaySeconds: 30,
                timeoutSeconds: 3,
              },
              ports: [
                {
                  containerPort: 5601,
                  name: 'kibana'
                },
              ],
              resources: {
                limits: {
                  memory: '1Gi',
                },
                requests: {
                  cpu: '100m',
                },
              },
            },
          ],
        },
      },
    },
  },
  service: ok.Service(name, namespace) {
    metadata+: { namespace: namespace },
    target_pod: $.deployment.spec.template,
    port: 8080,
  },
  ingress: ok.ContourIngress(
    name,
    namespace,
    tlsSecret = 'kibana-%s-tls' % [namespace],
  ) {
    host:: host,
    metadata+: {
      annotations+: {
        'contour.heptio.com/request-timeout': 'infinity',
      },
    },
    spec+: {
      rules: [
        {
          host: host,
          http: {
            paths: [
              {
                backend: {
                  serviceName: 'kibana',
                  servicePort: 8080,
                },
              },
            ],
          },
        },
      ],
    },
  },
};

ok.List() { items_: all('kibana', 'monitoring'), }

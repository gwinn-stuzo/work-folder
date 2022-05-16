resource "kubernetes_service_account" "node_local_dns" {
  metadata {
    name      = "node-local-dns"
    namespace = "kube-system"

    labels = {
      "addonmanager.kubernetes.io/mode" = "Reconcile"

      "kubernetes.io/cluster-service" = "true"
    }
  }
}

resource "kubernetes_service" "kube_dns_upstream" {
  metadata {
    name      = "kube-dns-upstream"
    namespace = "kube-system"

    labels = {
      "addonmanager.kubernetes.io/mode" = "Reconcile"

      k8s-app = "kube-dns"

      "kubernetes.io/cluster-service" = "true"

      "kubernetes.io/name" = "KubeDNSUpstream"
    }
  }

  spec {
    port {
      name        = "dns"
      protocol    = "UDP"
      port        = 53
      target_port = "53"
    }

    port {
      name        = "dns-tcp"
      protocol    = "TCP"
      port        = 53
      target_port = "53"
    }

    selector = {
      k8s-app = "kube-dns"
    }
  }
}

resource "kubernetes_config_map" "node_local_dns" {
  metadata {
    name      = "node-local-dns"
    namespace = "kube-system"

    labels = {
      "addonmanager.kubernetes.io/mode" = "Reconcile"
    }
  }

  data = {
    Corefile = "cluster.local:53 {\n    errors\n    cache {\n            success 9984 30\n            denial 9984 5\n    }\n    reload\n    loop\n    bind 169.254.0.1 172.20.0.10\n    forward . __PILLAR__CLUSTER__DNS__ {\n            force_tcp\n    }\n    prometheus :9253\n    health 169.254.0.1:8080\n    }\nin-addr.arpa:53 {\n    errors\n    cache 30\n    reload\n    loop\n    bind 169.254.0.1 172.20.0.10\n    forward . __PILLAR__CLUSTER__DNS__ {\n            force_tcp\n    }\n    prometheus :9253\n    }\nip6.arpa:53 {\n    errors\n    cache 30\n    reload\n    loop\n    bind 169.254.0.1 172.20.0.10\n    forward . __PILLAR__CLUSTER__DNS__ {\n            force_tcp\n    }\n    prometheus :9253\n    }\n.:53 {\n    errors\n    cache 30\n    reload\n    loop\n    bind 169.254.0.1 172.20.0.10\n    forward . __PILLAR__UPSTREAM__SERVERS__\n    prometheus :9253\n    }\n"
  }
}

resource "kubernetes_daemonset" "node_local_dns" {
  metadata {
    name      = "node-local-dns"
    namespace = "kube-system"

    labels = {
      "addonmanager.kubernetes.io/mode" = "Reconcile"

      k8s-app = "node-local-dns"

      "kubernetes.io/cluster-service" = "true"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "node-local-dns"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "node-local-dns"
        }

        annotations = {
          "prometheus.io/port" = "9253"

          "prometheus.io/scrape" = "true"
        }
      }

      spec {
        volume {
          name = "xtables-lock"

          host_path {
            path = "/run/xtables.lock"
            type = "FileOrCreate"
          }
        }

        volume {
          name = "kube-dns-config"

          config_map {
            name     = "kube-dns"
            optional = true
          }
        }

        volume {
          name = "config-volume"

          config_map {
            name = "node-local-dns"

            items {
              key  = "Corefile"
              path = "Corefile.base"
            }
          }
        }

        container {
          name  = "node-cache"
          image = "k8s.gcr.io/dns/k8s-dns-node-cache:1.21.1"
          args  = ["-localip", "169.254.0.1,172.20.0.10", "-conf", "/etc/Corefile", "-upstreamsvc", "kube-dns-upstream"]

          port {
            name           = "dns"
            container_port = 53
            protocol       = "UDP"
          }

          port {
            name           = "dns-tcp"
            container_port = 53
            protocol       = "TCP"
          }

          port {
            name           = "metrics"
            container_port = 9253
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu = "25m"

              memory = "5Mi"
            }
          }

          volume_mount {
            name       = "xtables-lock"
            mount_path = "/run/xtables.lock"
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/coredns"
          }

          volume_mount {
            name       = "kube-dns-config"
            mount_path = "/etc/kube-dns"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "8080"
              host = "169.254.0.1"
            }

            initial_delay_seconds = 60
            timeout_seconds       = 5
          }

          security_context {
            privileged = true
          }
        }

        dns_policy           = "Default"
        service_account_name = "node-local-dns"
        host_network         = true

        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "eks.amazonaws.com/compute-type"
                  operator = "NotIn"
                  values   = ["fargate"]
                }
              }
            }
          }
        }

        toleration {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }

        toleration {
          operator = "Exists"
          effect   = "NoExecute"
        }

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }

        priority_class_name = "system-node-critical"
      }
    }

    strategy {
      rolling_update {
        max_unavailable = "10%"
      }
    }
  }
}

resource "kubernetes_service" "node_local_dns" {
  metadata {
    name      = "node-local-dns"
    namespace = "kube-system"

    labels = {
      k8s-app = "node-local-dns"
    }

    annotations = {
      "prometheus.io/port" = "9253"

      "prometheus.io/scrape" = "true"
    }
  }

  spec {
    port {
      name        = "metrics"
      port        = 9253
      target_port = "9253"
    }

    selector = {
      k8s-app = "node-local-dns"
    }

    cluster_ip = "None"
  }
}


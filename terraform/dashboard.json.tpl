{
  "displayName": "Claude Code Usage Dashboard",
  "labels": {
    "claude-code": ""
  },
  "mosaicLayout": {
    "columns": 48,
    "tiles": [
      {
        "xPos": 0,
        "yPos": 0,
        "width": 48,
        "height": 4,
        "widget": {
          "title": "",
          "id": "header-text",
          "text": {
            "content": "# Claude Code Usage Dashboard\nReal-time monitoring of Claude Code sessions, costs, tokens, and productivity metrics.",
            "format": "MARKDOWN",
            "style": {
              "backgroundColor": "#1A237E",
              "textColor": "#FFFFFF",
              "horizontalAlignment": "H_LEFT",
              "verticalAlignment": "V_CENTER",
              "padding": "P_MEDIUM",
              "fontSize": "FS_LARGE"
            }
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 4,
        "width": 12,
        "height": 8,
        "widget": {
          "title": "Total Sessions",
          "id": "scorecard-sessions",
          "scorecard": {
            "timeSeriesQuery": {
              "prometheusQuery": "sum(increase(claude_code_session_count_total[1h]))",
              "unitOverride": ""
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            },
            "thresholds": []
          }
        }
      },
      {
        "xPos": 12,
        "yPos": 4,
        "width": 12,
        "height": 8,
        "widget": {
          "title": "Total Cost (USD)",
          "id": "scorecard-cost",
          "scorecard": {
            "timeSeriesQuery": {
              "prometheusQuery": "sum(increase(claude_code_cost_usage_USD_total[1h]))",
              "unitOverride": ""
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            },
            "thresholds": [
              {
                "label": "Warning",
                "value": 50,
                "color": "YELLOW",
                "direction": "ABOVE",
                "targetAxis": "Y1"
              },
              {
                "label": "Critical",
                "value": 100,
                "color": "RED",
                "direction": "ABOVE",
                "targetAxis": "Y1"
              }
            ]
          }
        }
      },
      {
        "xPos": 24,
        "yPos": 4,
        "width": 12,
        "height": 8,
        "widget": {
          "title": "Total Tokens Used",
          "id": "scorecard-tokens",
          "scorecard": {
            "timeSeriesQuery": {
              "prometheusQuery": "sum(increase(claude_code_token_usage_tokens_total[1h]))",
              "unitOverride": ""
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            },
            "thresholds": []
          }
        }
      },
      {
        "xPos": 36,
        "yPos": 4,
        "width": 12,
        "height": 8,
        "widget": {
          "title": "Active Time (hours)",
          "id": "scorecard-active-time",
          "scorecard": {
            "timeSeriesQuery": {
              "prometheusQuery": "sum(increase(claude_code_active_time_seconds_total[1h])) / 3600",
              "unitOverride": ""
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            },
            "thresholds": []
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 12,
        "width": 48,
        "height": 4,
        "widget": {
          "title": "",
          "id": "section-cost",
          "text": {
            "content": "## Cost & Token Usage",
            "format": "MARKDOWN",
            "style": {
              "backgroundColor": "#E8EAF6",
              "textColor": "#1A237E",
              "horizontalAlignment": "H_LEFT",
              "verticalAlignment": "V_CENTER",
              "padding": "P_MEDIUM",
              "fontSize": "FS_LARGE"
            }
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 16,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Cost Over Time (USD)",
          "id": "chart-cost-over-time",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (model) (increase(claude_code_cost_usage_USD_total[5m]))"
                },
                "plotType": "STACKED_AREA",
                "legendTemplate": "$${labels.model}",
                "minAlignmentPeriod": "300s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "USD",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 24,
        "yPos": 16,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Token Usage by Type",
          "id": "chart-tokens-by-type",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (type) (increase(claude_code_token_usage_tokens_total[5m]))"
                },
                "plotType": "STACKED_BAR",
                "legendTemplate": "$${labels.type}",
                "minAlignmentPeriod": "300s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Tokens",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 32,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Cost by Model",
          "id": "chart-cost-by-model",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (model) (increase(claude_code_cost_usage_USD_total[1h]))"
                },
                "plotType": "STACKED_BAR",
                "legendTemplate": "$${labels.model}",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "USD",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 24,
        "yPos": 32,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Token Usage by Model",
          "id": "chart-tokens-by-model",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (model) (increase(claude_code_token_usage_tokens_total[5m]))"
                },
                "plotType": "STACKED_BAR",
                "legendTemplate": "$${labels.model}",
                "minAlignmentPeriod": "300s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Tokens",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 48,
        "width": 48,
        "height": 4,
        "widget": {
          "title": "",
          "id": "section-sessions",
          "text": {
            "content": "## Sessions & Activity",
            "format": "MARKDOWN",
            "style": {
              "backgroundColor": "#E8EAF6",
              "textColor": "#1A237E",
              "horizontalAlignment": "H_LEFT",
              "verticalAlignment": "V_CENTER",
              "padding": "P_MEDIUM",
              "fontSize": "FS_LARGE"
            }
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 52,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Sessions Over Time",
          "id": "chart-sessions-over-time",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum(increase(claude_code_session_count_total[1h]))"
                },
                "plotType": "STACKED_BAR",
                "legendTemplate": "Sessions",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Sessions",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 24,
        "yPos": 52,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Active Time by Type",
          "id": "chart-active-time-by-type",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (type) (increase(claude_code_active_time_seconds_total[5m])) / 60"
                },
                "plotType": "STACKED_AREA",
                "legendTemplate": "$${labels.type}",
                "minAlignmentPeriod": "300s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Minutes",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 68,
        "width": 48,
        "height": 4,
        "widget": {
          "title": "",
          "id": "section-productivity",
          "text": {
            "content": "## Productivity",
            "format": "MARKDOWN",
            "style": {
              "backgroundColor": "#E8EAF6",
              "textColor": "#1A237E",
              "horizontalAlignment": "H_LEFT",
              "verticalAlignment": "V_CENTER",
              "padding": "P_MEDIUM",
              "fontSize": "FS_LARGE"
            }
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 72,
        "width": 16,
        "height": 16,
        "widget": {
          "title": "Lines of Code Modified",
          "id": "chart-lines-of-code",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (type) (increase(claude_code_lines_of_code_count_total[1h]))"
                },
                "plotType": "STACKED_BAR",
                "legendTemplate": "$${labels.type}",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Lines",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 16,
        "yPos": 72,
        "width": 16,
        "height": 16,
        "widget": {
          "title": "Code Edit Tool Decisions",
          "id": "chart-code-edit-decisions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (decision) (increase(claude_code_code_edit_tool_decision_total[1h]))"
                },
                "plotType": "STACKED_BAR",
                "legendTemplate": "$${labels.decision}",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Decisions",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 32,
        "yPos": 72,
        "width": 16,
        "height": 16,
        "widget": {
          "title": "Code Edits by Language",
          "id": "chart-edits-by-language",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum by (language) (increase(claude_code_code_edit_tool_decision_total[1h]))"
                },
                "plotType": "STACKED_BAR",
                "legendTemplate": "$${labels.language}",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Edits",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 88,
        "width": 48,
        "height": 4,
        "widget": {
          "title": "",
          "id": "section-efficiency",
          "text": {
            "content": "## Cost Efficiency",
            "format": "MARKDOWN",
            "style": {
              "backgroundColor": "#E8EAF6",
              "textColor": "#1A237E",
              "horizontalAlignment": "H_LEFT",
              "verticalAlignment": "V_CENTER",
              "padding": "P_MEDIUM",
              "fontSize": "FS_LARGE"
            }
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 92,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Cost per Session (USD)",
          "id": "chart-cost-per-session",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum(increase(claude_code_cost_usage_USD_total[1h])) / clamp_min(sum(increase(claude_code_session_count_total[1h])), 1)"
                },
                "plotType": "LINE",
                "legendTemplate": "Cost per Session",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "USD / Session",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 24,
        "yPos": 92,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Tokens per Session",
          "id": "chart-tokens-per-session",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum(increase(claude_code_token_usage_tokens_total[1h])) / clamp_min(sum(increase(claude_code_session_count_total[1h])), 1)"
                },
                "plotType": "LINE",
                "legendTemplate": "Tokens per Session",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Tokens / Session",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 0,
        "yPos": 108,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Lines of Code per Dollar",
          "id": "chart-loc-per-dollar",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum(increase(claude_code_lines_of_code_count_total[1h])) / clamp_min(sum(increase(claude_code_cost_usage_USD_total[1h])), 0.01)"
                },
                "plotType": "LINE",
                "legendTemplate": "Lines / USD",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "Lines / USD",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      },
      {
        "xPos": 24,
        "yPos": 108,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "Cache Hit Ratio (Tokens)",
          "id": "chart-cache-ratio",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "prometheusQuery": "sum(increase(claude_code_token_usage_tokens_total{type=\"cacheRead\"}[1h])) / clamp_min(sum(increase(claude_code_token_usage_tokens_total{type=\"input\"}[1h])) + sum(increase(claude_code_token_usage_tokens_total{type=\"cacheRead\"}[1h])), 1) * 100"
                },
                "plotType": "LINE",
                "legendTemplate": "Cache Hit %",
                "minAlignmentPeriod": "3600s",
                "targetAxis": "Y1"
              }
            ],
            "yAxis": {
              "label": "%",
              "scale": "LINEAR"
            },
            "chartOptions": {
              "mode": "COLOR",
              "displayHorizontal": false
            },
            "timeshiftDuration": "0s"
          }
        }
      }
    ]
  }
}

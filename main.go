// Submit metrics returns "Payload accepted" response

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	datadog "github.com/DataDog/datadog-api-client-go/api/v2/datadog"
)

type datadogSetup struct {
	Config *datadog.Configuration
	Client *datadog.APIClient
}

var defaultDatadogSetup datadogSetup

func setEnv() {
	os.Setenv("DD_SITE", "localhost")
	// needs "DD_API_KEY" and "DD_APP_KEY" set by non-checked-in env
}

func localHostConfiguration() *datadog.Configuration {
	conf := datadog.NewConfiguration()
	conf.Servers = datadog.ServerConfigurations{
		{
			URL:         "http://{site}",
			Description: "No description provided",
			Variables: map[string]datadog.ServerVariable{
				"site": {
					Description:  "The regional site for Datadog customers.",
					DefaultValue: "api.datadoghq.com",
					EnumValues: []string{
						"api.datadoghq.com",
						"api.us3.datadoghq.com",
						"api.us5.datadoghq.com",
						"api.datadoghq.eu",
						"api.ddog-gov.com",
						"localhost",
					},
				},
			},
		},
		{
			URL:         "{protocol}://{name}",
			Description: "No description provided",
			Variables: map[string]datadog.ServerVariable{
				"name": {
					Description:  "Full site DNS name.",
					DefaultValue: "localhost",
				},
				"protocol": {
					Description:  "The protocol for accessing the API.",
					DefaultValue: "http",
				},
			},
		},
		{
			URL:         "http://{site}",
			Description: "No description provided",
			Variables: map[string]datadog.ServerVariable{
				"site": {
					Description:  "Any Datadog deployment.",
					DefaultValue: "api.datadoghq.com",
				},
			},
		},
	}
	return conf
}

func sendBody(ctx context.Context, body datadog.MetricPayload) error {
	payload, resp, err := defaultDatadogSetup.Client.MetricsApi.SubmitMetrics(ctx, body, *datadog.NewSubmitMetricsOptionalParameters())

	fmt.Fprintf(os.Stderr, "Full HTTP response: %v\n", resp)
	fmt.Fprintf(os.Stderr, "Intake Payload object: %v\n", payload)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error when calling `MetricsApi.SubmitMetrics`: %v\n", err)
		fmt.Fprintf(os.Stderr, "Full HTTP response: %v\n", resp)
		return err
	}

	payloadContent, _ := json.MarshalIndent(payload, "", "  ")
	fmt.Fprintf(os.Stdout, "Intake Payload from `MetricsApi.SubmitMetrics`: %s\n", payloadContent)
	clientConfig := defaultDatadogSetup.Client.GetConfig()
	fmt.Fprintf(os.Stdout, "Datadog Client Configuration:\n%s\n", clientConfig)
	return nil
}

func main() {
	setEnv()
	ctx := datadog.NewDefaultContext(context.Background())
	defaultDatadogSetup.Config = localHostConfiguration()
	defaultDatadogSetup.Client = datadog.NewAPIClient(defaultDatadogSetup.Config)

	bodies := [3]datadog.MetricPayload{
		datadog.MetricPayload{
			Series: []datadog.MetricSeries{
				{
					Metric: "fnord.count",
					Type:   datadog.METRICINTAKETYPE_COUNT.Ptr(),
					Points: []datadog.MetricPoint{
						{
							Timestamp: datadog.PtrInt64(time.Now().Unix() - 90),
							Value:     datadog.PtrFloat64(3.0),
						},
					},
					Tags: []string{
						"license-digest:deadbeef",
					},
				},
			},
		},
		datadog.MetricPayload{
			Series: []datadog.MetricSeries{
				{
					Metric: "fnord.count",
					Type:   datadog.METRICINTAKETYPE_COUNT.Ptr(),
					Points: []datadog.MetricPoint{
						{
							Timestamp: datadog.PtrInt64(time.Now().Unix() - 40),
							Value:     datadog.PtrFloat64(2.0),
						},
					},
					Tags: []string{
						"license-digest:decafbed",
					},
				},
			},
		},
		datadog.MetricPayload{
			Series: []datadog.MetricSeries{
				{
					Metric: "fnord.count",
					Type:   datadog.METRICINTAKETYPE_COUNT.Ptr(),
					Points: []datadog.MetricPoint{
						{
							Timestamp: datadog.PtrInt64(time.Now().Unix()),
							Value:     datadog.PtrFloat64(18.0),
						},
					},
					Tags: []string{
						"license-digest:fadedcab",
					},
				},
			},
		},
	}

	for _, body := range bodies {
		sendBody(ctx, body)
	}
}

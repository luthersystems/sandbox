//// Validate API key returns "OK" response
//
//package main
//
//import (
//    "context"
//    "encoding/json"
//    "fmt"
//    "os"
//
//    datadog "github.com/DataDog/datadog-api-client-go/api/v1/datadog"
//)
//
//func main() {
//    ctx := datadog.NewDefaultContext(context.Background())
//    configuration := datadog.NewConfiguration()
//    apiClient := datadog.NewAPIClient(configuration)
//    resp, r, err := apiClient.AuthenticationApi.Validate(ctx)
//
//    if err != nil {
//        fmt.Fprintf(os.Stderr, "Error when calling `AuthenticationApi.Validate`: %v\n", err)
//        fmt.Fprintf(os.Stderr, "Full HTTP response: %v\n", r)
//    }
//
//    responseContent, _ := json.MarshalIndent(resp, "", "  ")
//    fmt.Fprintf(os.Stdout, "Response from `AuthenticationApi.Validate`:\n%s\n", responseContent)
//}

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

func main() {
    ctx := datadog.NewDefaultContext(context.Background())
    configuration := datadog.NewConfiguration()
    apiClient := datadog.NewAPIClient(configuration)

    bodies := [3]datadog.MetricPayload{
        datadog.MetricPayload{
            Series: []datadog.MetricSeries{
                {
                    Metric: "fnord.count",
                    Type:   datadog.METRICINTAKETYPE_COUNT.Ptr(),
                    Points: []datadog.MetricPoint{
                        {
                            Timestamp: datadog.PtrInt64(time.Now().Unix()),
                            Value:     datadog.PtrFloat64(3.0),
                        },
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
                            Timestamp: datadog.PtrInt64(time.Now().Unix()+40),
                            Value:     datadog.PtrFloat64(2.0),
                        },
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
                            Timestamp: datadog.PtrInt64(time.Now().Unix()+90),
                            Value:     datadog.PtrFloat64(18.0),
                        },
                    },
                },
            },
        },
    }

    for _, body := range bodies {
        resp, r, err := apiClient.MetricsApi.SubmitMetrics(ctx, body, *datadog.NewSubmitMetricsOptionalParameters())

        if err != nil {
            fmt.Fprintf(os.Stderr, "Error when calling `MetricsApi.SubmitMetrics`: %v\n", err)
            fmt.Fprintf(os.Stderr, "Full HTTP response: %v\n", r)
        }

        responseContent, _ := json.MarshalIndent(resp, "", "  ")
        fmt.Fprintf(os.Stdout, "Response from `MetricsApi.SubmitMetrics`:\n%s\n", responseContent)
        fmt.Fprintf(os.Stderr, "Full HTTP response: %v\n", r)
    }
}

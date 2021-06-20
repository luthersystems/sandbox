// Copyright © 2021 Luther Systems, Ltd. All right reserved.

package swagger

import (
	"bytes"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"

	"github.com/sirupsen/logrus"
)

//go:embed *.swagger.json
var swaggerJSON embed.FS

// HTTPHandler returns an endpoint handler that writes the specified swagger
// service definition to w.
func HTTPHandler(svc string) (http.Handler, error) {
	b, err := fs.ReadFile(swaggerJSON, string(svc+".swagger.json"))
	if err != nil {
		return nil, err
	}
	if !json.Valid(b) {
		return nil, fmt.Errorf("document does not contain a valid json object")
	}
	return svcHandler(b), nil
}

type svcHandler []byte

func (b svcHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_, err := io.Copy(w, bytes.NewReader([]byte(b)))
	if err != nil {
		logrus.Error(err)
	}
}

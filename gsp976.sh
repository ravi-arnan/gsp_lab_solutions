#!/usr/bin/env bash
# GSP976 - Optimizing Applications Using Cloud Profiler
#
#   bash gsp976.sh
#
# Checkpoint:
#   Task 1 - Enable the Cloud Profiler API

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

echo "Project ID : $PROJECT_ID"
gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

# ----------------------------------------------------------------- Task 1: Aktifkan Cloud Profiler API
step "Task 1: Mengaktifkan Cloud Profiler API (Checkpoint)"

echo "Mengaktifkan service cloudprofiler.googleapis.com..."
gcloud services enable cloudprofiler.googleapis.com --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 1b: Unduh Sample Repository
step "Task 1b: Mengunduh Sample Application Go (shakesapp)"

cd ~
if [[ ! -d "$HOME/golang-samples" ]]; then
  echo "Meng-clone repositori golang-samples..."
  git clone https://github.com/GoogleCloudPlatform/golang-samples.git
else
  echo "Direktori golang-samples sudah ada."
fi

APP_DIR="$HOME/golang-samples/profiler/shakesapp"
cd "$APP_DIR"

# Jalankan 1 round singkat versi 1 untuk inisialisasi awal ke Cloud Profiler
echo "Mengirim profil inisialisasi awal versi 1 (1 round)..."
timeout 45 go run . -version 1 -num_rounds 1 || true

# ----------------------------------------------------------------- Task 3 & 6: Optimasi CPU Time & Heap Allocation
step "Task 3 & 6: Menerapkan Optimasi strings.Contains & In-Memory Caching"

SERVER_GO="$APP_DIR/shakesapp/server.go"

echo "Memperbarui shakesapp/server.go dengan kode teroptimasi..."
cat << 'EOF_SERVER' > "$SERVER_GO"
// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Package shakesapp defines a server which can be queried to determined
// many times a string appears in the works of Shakespeare, and a client
// which can be used to send load to that server.
package shakesapp

import (
	"context"
	"fmt"
	"io/ioutil"
	"strings"

	"cloud.google.com/go/storage"
	"google.golang.org/api/iterator"
	"google.golang.org/api/option"
)

// server is an implementation of the server for ShakespeareService (defined
// in shakesapp.proto).
type server struct{}

// NewServer returns an implementation of the server for ShakespeareService
// (defined in shakesapp.proto).
func NewServer() ShakespeareServiceServer {
	return &server{}
}

const bucketName = "dataflow-samples"
const bucketPrefix = "shakespeare/"

// Global cache variable to store the results of the initial file read
var files []string

// GetMatchCount implements a server for ShakespeareService.
func (s *server) GetMatchCount(ctx context.Context, req *ShakespeareRequest) (*ShakespeareResponse, error) {
	resp := &ShakespeareResponse{}
	texts, err := readFiles(ctx, bucketName, bucketPrefix)
	if err != nil {
		return resp, fmt.Errorf("fails to read files: %s", err)
	}
	for _, text := range texts {
		for _, line := range strings.Split(text, "\n") {
			line, query := strings.ToLower(line), strings.ToLower(req.Query)
			// Optimized: using strings.Contains instead of regexp.MatchString
			if strings.Contains(line, query) {
				resp.MatchCount++
			}
		}
	}
	return resp, nil
}

// readFiles reads the content of files within the specified bucket with the
// specified prefix path in parallel and returns their content. It fails if
// operations to find or read any of the files fails.
func readFiles(ctx context.Context, bucketName, prefix string) ([]string, error) {
	// Return if already cached in memory
	if files != nil {
		return files, nil
	}

	type resp struct {
		s   string
		err error
	}

	client, err := storage.NewClient(ctx, option.WithoutAuthentication())
	if err != nil {
		return []string{}, fmt.Errorf("failed to create storage client: %s", err)
	}
	defer client.Close()

	bucket := client.Bucket(bucketName)

	var paths []string
	it := bucket.Objects(ctx, &storage.Query{Prefix: bucketPrefix})
	for {
		attrs, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return []string{}, fmt.Errorf("failed to iterate over files in %s starting with %s: %w", bucketName, prefix, err)
		}
		if attrs.Name != "" {
			paths = append(paths, attrs.Name)
		}
	}

	resps := make(chan resp)
	for _, path := range paths {
		go func(path string) {
			obj := bucket.Object(path)
			r, err := obj.NewReader(ctx)
			if err != nil {
				resps <- resp{"", err}
			}
			defer r.Close()
			data, err := ioutil.ReadAll(r)
			resps <- resp{string(data), err}
		}(path)
	}

	files = make([]string, len(paths))
	for i := 0; i < len(paths); i++ {
		r := <-resps
		if r.err != nil {
			return nil, r.err
		}
		files[i] = r.s
	}
	return files, nil
}
EOF_SERVER

# ----------------------------------------------------------------- Task 7: Uji Eksekusi Versi Teroptimasi
step "Task 7: Eksekusi Aplikasi Teroptimasi (Versi 4)"

echo "Menjalankan aplikasi teroptimasi (versi 4, 3 rounds) untuk verifikasi kecepatan tinggi..."
timeout 30 go run . -version 4 -num_rounds 3 -heap -heap_alloc || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Enable the Cloud Profiler API (Task 1)
==============================================================
EOF

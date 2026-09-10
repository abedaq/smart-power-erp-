package ui

import (
	"embed"
	"io/fs"
	"net/http"
)

//go:embed dist/*
var distEmbedFS embed.FS

func GetFS() http.FileSystem {
	sub, err := fs.Sub(distEmbedFS, "dist")
	if err != nil {
		panic(err)
	}
	return http.FS(sub)
}
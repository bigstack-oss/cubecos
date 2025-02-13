package tgz

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func createFile(header *tar.Header, reader *tar.Reader, target string) error {
	file, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY, os.FileMode(header.Mode))
	if err != nil {
		return fmt.Errorf("failed to create file: %s", err.Error())
	}

	defer file.Close()
	if _, err := io.Copy(file, reader); err != nil {
		return fmt.Errorf("failed to write file content: %s", err.Error())
	}

	return nil
}

func unloadBlobs(reader *tar.Reader, dest string) error {
	for {
		header, err := reader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("error reading tar archive: %s", err.Error())
		}

		target := filepath.Join(dest, header.Name)
		switch header.Typeflag {
		case tar.TypeDir:
			err := os.MkdirAll(target, os.FileMode(header.Mode))
			if err != nil {
				return fmt.Errorf("failed to create directory: %s", err.Error())
			}
		case tar.TypeReg:
			err := createFile(header, reader, target)
			if err != nil {
				return err
			}
		default:
			return fmt.Errorf("unknown file type in tar: %v", header.Typeflag)
		}
	}

	return nil
}

func Decompress(src string, dest string) error {
	file, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("failed to open the tgz file: %s", err.Error())
	}

	defer file.Close()
	gzr, err := gzip.NewReader(file)
	if err != nil {
		return fmt.Errorf("failed to create gzip reader: %s", err.Error())
	}

	defer gzr.Close()
	reader := tar.NewReader(gzr)
	return unloadBlobs(reader, dest)
}

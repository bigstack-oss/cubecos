package kube

import "errors"

var (
	ErrCpuQuotaExceeded                     = errors.New("cpu quota exceeded")
	ErrMemoryQuotaExceeded                  = errors.New("memory quota exceeded")
	ErrEphemeralStorageStorageQuotaExceeded = errors.New("ephemeral-storage quota exceeded")
)

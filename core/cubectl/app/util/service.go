package util

import (
	"net"
	"strconv"
	"time"

	"github.com/avast/retry-go"
	"go.uber.org/zap"
)

func Retry(f func() error, attempts uint) error {
	if err := retry.Do(
		f,
		retry.Attempts(attempts),
		retry.Delay(1*time.Second),
		retry.MaxDelay(15*time.Second),
		retry.OnRetry(func(n uint, err error) {
			zap.L().Debug("Retrying", zap.Uint("attempts", n), zap.Error(err))
		}),
	); err != nil {
		return err
	}

	return nil
}

func CheckService(host string, port int, attempts uint) error {
	if err := Retry(
		func() error {
			conn, err := net.Dial("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
			if err != nil {
				return err
			}
			defer conn.Close()

			return nil
		},
		attempts,
	); err != nil {
		return err
	}

	return nil
}

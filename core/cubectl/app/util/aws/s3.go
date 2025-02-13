package aws

import (
	"bytes"
	"context"
	"crypto/tls"
	"net/http"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	v4 "github.com/aws/aws-sdk-go-v2/aws/signer/v4"
	awshttp "github.com/aws/aws-sdk-go-v2/aws/transport/http"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

func NewS3Client(opts ...Option) (*Helper, error) {
	h := &Helper{}
	h.Options = Options{}
	for _, opt := range opts {
		opt(&h.Options)
	}

	cli, err := newS3Client(h.Options)
	if err != nil {
		return nil, err
	}

	h.S3Client = cli
	h.S3PresignedClient = s3.NewPresignClient(cli)
	h.AwsS3Client = cli

	return h, nil
}

func newS3Client(opts Options) (*s3.Client, error) {
	cfg, err := newAwsConfig(opts)
	if err != nil {
		return nil, err
	}

	cli := s3.NewFromConfig(*cfg)
	if opts.EnableCustomURL {
		cli = s3.NewFromConfig(
			*cfg,
			func(o *s3.Options) { o.BaseEndpoint = &opts.S3Url },
		)
	}

	return cli, nil
}

func newAwsConfig(opts Options) (*aws.Config, error) {
	cfg, err := config.LoadDefaultConfig(
		context.Background(),
		config.WithRegion(opts.Region),
	)
	if err != nil {
		return nil, err
	}

	if opts.InsecureSkipVerify {
		customTransport := &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: opts.InsecureSkipVerify},
		}
		cfg.HTTPClient = awshttp.NewBuildableClient().WithTransportOptions(
			func(tr *http.Transport) { tr.TLSClientConfig = customTransport.TLSClientConfig },
		)
	}

	if opts.EnableStaticCreds {
		cfg.Credentials = credentials.NewStaticCredentialsProvider(
			opts.AccessKey,
			opts.SecretKey,
			"",
		)
	}

	return &cfg, nil
}

func (h *Helper) CreateBucket(bucketName string) (*s3.CreateBucketOutput, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()
	return h.S3Client.CreateBucket(
		ctx,
		&s3.CreateBucketInput{Bucket: &bucketName},
	)
}

func (h *Helper) PutObject(bucket, key string, body []byte) (*s3.PutObjectOutput, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()
	return h.S3Client.PutObject(
		ctx,
		&s3.PutObjectInput{
			Bucket: &bucket,
			Key:    &key,
			Body:   bytes.NewBuffer(body),
		},
		s3.WithAPIOptions(v4.SwapComputePayloadSHA256ForUnsignedPayloadMiddleware),
	)
}

func (h *Helper) DeleteObject(bucket, key string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()

	_, err := h.S3Client.DeleteObject(
		ctx,
		&s3.DeleteObjectInput{
			Bucket: &bucket,
			Key:    &key,
		},
	)

	return err
}

func (h *Helper) GenPresignedUrl(bucket, key string, expires time.Duration) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*10)
	defer cancel()

	object, err := h.S3PresignedClient.PresignGetObject(
		ctx,
		&s3.GetObjectInput{Bucket: &bucket, Key: &key},
		s3.WithPresignExpires(expires),
	)
	if err != nil {
		return "", err
	}

	return object.URL, nil
}

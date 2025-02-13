package aws

var (
	Opts *Options
)

type Option func(*Options)

type Options struct {
	Region string
	S3Url  string

	AccessKey string
	SecretKey string

	EnableCustomURL    bool
	EnableStaticCreds  bool
	InsecureSkipVerify bool
}

func Region(region string) Option {
	return func(o *Options) {
		o.Region = region
	}
}

func S3Url(s3Url string) Option {
	return func(o *Options) {
		o.S3Url = s3Url
	}
}

func AccessKey(accessKey string) Option {
	return func(o *Options) {
		o.AccessKey = accessKey
	}
}

func SecretKey(secretKey string) Option {
	return func(o *Options) {
		o.SecretKey = secretKey
	}
}

func EnableCustomURL(enable bool) Option {
	return func(o *Options) {
		o.EnableCustomURL = enable
	}
}

func EnableStaticCreds(enable bool) Option {
	return func(o *Options) {
		o.EnableStaticCreds = enable
	}
}

func InsecureSkipVerify(skip bool) Option {
	return func(o *Options) {
		o.InsecureSkipVerify = skip
	}
}

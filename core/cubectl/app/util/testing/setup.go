package testing

import (
	"io/ioutil"
)

func GenerateSettingsMap(file string, tuneMap map[string]string) error {
	var content string
	for k, v := range tuneMap {
		content += k + "=" + v + "\n"
	}

	return GenerateSettingsRaw(file, content)
}

func GenerateSettingsRaw(file string, str string) error {
	err := ioutil.WriteFile(file, []byte(str), 0644)
	return err
}

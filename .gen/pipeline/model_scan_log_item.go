/*
 * Pipeline API
 *
 * Pipeline v0.3.0 swagger
 *
 * API version: 0.26.0
 * Contact: info@banzaicloud.com
 */

// Code generated by OpenAPI Generator (https://openapi-generator.tech); DO NOT EDIT.

package pipeline

type ScanLogItem struct {
	ReleaseName string `json:"releaseName,omitempty"`
	Resource string `json:"resource,omitempty"`
	Image []ScanLogItemImage `json:"image,omitempty"`
	Result []string `json:"result,omitempty"`
	Action string `json:"action,omitempty"`
}

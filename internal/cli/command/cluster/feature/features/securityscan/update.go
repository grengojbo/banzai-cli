// Copyright © 2019 Banzai Cloud
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package securityscan

import (
	"context"
	"encoding/json"
	"fmt"

	"emperror.dev/errors"
	"github.com/AlecAivazis/survey/v2"
	"github.com/banzaicloud/banzai-cli/.gen/pipeline"
	"github.com/banzaicloud/banzai-cli/internal/cli"
	clustercontext "github.com/banzaicloud/banzai-cli/internal/cli/command/cluster/context"
	"github.com/banzaicloud/banzai-cli/internal/cli/utils"
	"github.com/mitchellh/mapstructure"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

func NewUpdateCommand(banzaiCli cli.Cli) *cobra.Command {
	options := updateOptions{}
	fu := MakeFeatureUpdater(banzaiCli)

	cmd := &cobra.Command{
		Use:     "update",
		Aliases: []string{"change", "modify", "set"},
		Short:   fmt.Sprintf("Update the %s feature of a cluster", featureName),
		Args:    cobra.NoArgs,
		RunE: func(_ *cobra.Command, args []string) error {
			return fu.runUpdate(options, args)
		},
	}

	options.Context = clustercontext.NewClusterContext(cmd, banzaiCli, fmt.Sprintf("update the %s cluster feature for", featureName))

	flags := cmd.Flags()
	flags.StringVarP(&options.filePath, "file", "f", "", "Feature specification file")

	return cmd
}

type updateOptions struct {
	clustercontext.Context
	filePath string
}

// featureUpdater struct for gathering helper operations for the feature update
type featureUpdater struct {
	specAssembler
}

func MakeFeatureUpdater(banzaiCLI cli.Cli) *featureUpdater {
	fu := new(featureUpdater)
	fu.banzaiCLI = banzaiCLI
	return fu
}

func (fu *featureUpdater) getSecurityScanFeature(orgID int32, clusterID int32) (map[string]interface{}, error) {

	clusterFeatureDetails, _, err := fu.banzaiCLI.Client().ClusterFeaturesApi.ClusterFeatureDetails(context.Background(), orgID, clusterID, featureName)
	if err != nil {
		return nil, errors.WrapIf(err, "failed to retrieve the feature to update")
	}

	return clusterFeatureDetails.Spec, nil
}

func ValidateUpdateClusterFeatureRequest(req interface{}) error {
	var request pipeline.UpdateClusterFeatureRequest
	if err := json.Unmarshal([]byte(req.(string)), &request); err != nil {
		return errors.WrapIf(err, "request is not valid JSON")
	}

	return nil
}

func (fu *featureUpdater) runUpdate(options updateOptions, args []string) error {
	if err := options.Init(args...); err != nil {
		return errors.Wrap(err, "failed to initialize options")
	}

	orgId := fu.banzaiCLI.Context().OrganizationID()
	clusterId := options.ClusterID()

	securityScanFeatureSpec, err := fu.getSecurityScanFeature(orgId, clusterId)
	if err != nil {
		return errors.WrapIf(err, "failed to update feature")
	}

	req := new(pipeline.UpdateClusterFeatureRequest)
	req.Spec = securityScanFeatureSpec

	if options.filePath == "" && fu.banzaiCLI.Interactive() {
		if err := fu.buildUpdateReqInteractively(options, req); err != nil {
			return errors.WrapIf(err, "failed to build update request interactively")
		}
	}

	if err := readUpdateReqFromFileOrStdin(options.filePath, req); err != nil {
		return errors.WrapIff(err, "failed to read %s cluster feature specification", featureName)
	}

	resp, err := fu.banzaiCLI.Client().ClusterFeaturesApi.UpdateClusterFeature(context.Background(), orgId, clusterId, featureName, *req)
	if err != nil {
		cli.LogAPIError(fmt.Sprintf("activate %s cluster feature", featureName), err, resp)
		log.Fatalf("could not activate %s cluster feature: %v", featureName, err)
	}

	log.Infof("feature %q started to update", featureName)

	return nil
}

func readUpdateReqFromFileOrStdin(filePath string, req *pipeline.UpdateClusterFeatureRequest) error {
	filename, raw, err := utils.ReadFileOrStdin(filePath)
	if err != nil {
		return errors.WrapIfWithDetails(err, "failed to read", "filename", filename)
	}

	if err := json.Unmarshal(raw, &req); err != nil {
		return errors.WrapIf(err, "failed to unmarshal input")
	}

	return nil
}

func (fu *featureUpdater) buildUpdateReqInteractively(_ updateOptions, req *pipeline.UpdateClusterFeatureRequest) error {
	var edit bool
	if err := survey.AskOne(
		&survey.Confirm{Message: "Edit the cluster feature update request in your text editor?"},
		&edit,
		survey.WithValidator(ValidateUpdateClusterFeatureRequest)); err != nil {
		return errors.WrapIf(err, "failure during survey")
	}

	if !edit {
		return fu.buildCustomAnchoreFeatureRequest(req)
	}

	content, err := json.MarshalIndent(*req, "", "  ")
	if err != nil {
		return errors.WrapIf(err, "failed to marshal request to JSON")
	}

	prompt := &survey.Editor{Default: string(content), HideDefault: true, AppendDefault: true}

	var updated string
	if err := survey.AskOne(prompt, &updated); err != nil {
		return errors.WrapIf(err, "failure during survey")
	}

	if err := json.Unmarshal([]byte(updated), req); err != nil {
		return errors.WrapIf(err, "failed to unmarshal JSON as request")
	}

	return nil
}

func (fu *featureUpdater) buildCustomAnchoreFeatureRequest(updateRequest *pipeline.UpdateClusterFeatureRequest) error {

	// get the type from the req
	securityFeatureSpec := new(SecurityScanFeatureSpec)
	if err := mapstructure.Decode(updateRequest.Spec, securityFeatureSpec); err != nil {
		return errors.WrapIf(err, "failed to decode the feature to update")
	}

	anchoreConfig, err := fu.askForAnchoreConfig(&securityFeatureSpec.CustomAnchore)
	if err != nil {
		return errors.WrapIf(err, "failed to read Anchore configuration details")
	}

	policy, err := fu.askForPolicy(&securityFeatureSpec.Policy)
	if err != nil {
		return errors.WrapIf(err, "failed to read Anchore Policy configuration details")
	}

	// todo whitelist updates not supported fro now
	webhookConfig, err := fu.askForWebHookConfig(&securityFeatureSpec.WebhookConfig)
	if err != nil {
		return errors.WrapIf(err, "failed to read webhook configuration")
	}

	securityScanFeatureRequest := new(SecurityScanFeatureSpec)
	securityScanFeatureRequest.CustomAnchore = *anchoreConfig
	securityScanFeatureRequest.Policy = *policy
	securityScanFeatureRequest.ReleaseWhiteList = securityFeatureSpec.ReleaseWhiteList
	securityScanFeatureRequest.WebhookConfig = *webhookConfig

	ssfMap, err := fu.securityScanSpecAsMap(securityScanFeatureRequest)
	if err != nil {
		return errors.WrapIf(err, "failed to transform request to map")
	}

	updateRequest.Spec = ssfMap

	return nil
}
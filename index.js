const path = require('path');
const core = require('@actions/core');
const aws = require('aws-sdk');
const tmp = require('tmp');
const fs = require('fs');

async function run() {
  try {

    const ssm_path = core.getInput('ssm-path', { required: true });
    const taskDefinitionFile = core.getInput('task-definition', { required: true });
    const containerName = core.getInput('container-name', { required: true });

    const ssm = new aws.SSM();

    function getSSMStuff(path, memo = [], nextToken) {
      return ssm
      .getParametersByPath({ Path: path, WithDecryption: true, Recursive: true, NextToken: nextToken, MaxResults: 10 })
      .promise()
      .then(({ Parameters, NextToken }) => {
        const newMemo = memo.concat(Parameters);
        return NextToken ? getSSMStuff(path, newMemo, NextToken) : newMemo;
      });
    }
    const allParams = await getSSMStuff(ssm_path,[])

    const parsedSsmParams = []
    for (eachParam in allParams) {
      const element = {}
      // console.log(allParams[eachParam]["Name"].replace(ssm_path.slice(-1) === '/' ? ssm_path: ssm_path + '/',''))
      element.name = allParams[eachParam]["Name"].replace(ssm_path.slice(-1) === '/' ? ssm_path: ssm_path + '/','')
      element.valueFrom = allParams[eachParam]["Value"]
      parsedSsmParams.push(element)
    }

    // Parse the task definition
    core.debug('Parsing task definition File');
    const taskDefPath = path.isAbsolute(taskDefinitionFile) ?
      taskDefinitionFile :
      path.join(process.env.GITHUB_WORKSPACE, taskDefinitionFile);
    if (!fs.existsSync(taskDefPath)) {
      throw new Error(`Task definition file does not exist: ${taskDefinitionFile}`);
    }
    const taskDefContents = require(taskDefPath);
    if (!Array.isArray(taskDefContents.containerDefinitions)) {
      throw new Error('Invalid task definition format: containerDefinitions section is not present or is not an array');
    }
    const containerDef = taskDefContents.containerDefinitions.find(function(element) {
      return element.name === containerName;
    });
    if (!containerDef) {
      throw new Error('Invalid task definition: Could not find container definition with matching name');
    }

    containerDef.secrets = parsedSsmParams;

    // Write out a new task definition file
    var updatedTaskDefFile = tmp.fileSync({
      tmpdir: process.env.RUNNER_TEMP,
      prefix: 'task-definition-',
      postfix: '.json',
      keep: true,
      discardDescriptor: true
    });
    const newTaskDefContents = JSON.stringify(taskDefContents, null, 2);
    fs.writeFileSync(updatedTaskDefFile.name, newTaskDefContents);
    core.setOutput('task-definition', updatedTaskDefFile.name);

  }
  catch (error) {
    core.setFailed(error.message);
  }
}

module.exports = run;

/* istanbul ignore next */
if (require.main === module) {
    run();
}
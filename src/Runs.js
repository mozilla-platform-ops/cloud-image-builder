import React from 'react'
import Run from './Run';

class Runs extends React.Component {
  render() {
    return (
      <ul>
        {
          this.props.runs.map(run => (
            <Run run={run} key={run.runId} taskId={this.props.taskId} rootUrl={this.props.rootUrl} />
          ))
        }
      </ul>
    );
  }
}

export default Runs;

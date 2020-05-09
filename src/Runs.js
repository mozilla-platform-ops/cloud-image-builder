import React from 'react'
import Run from './Run';

class Runs extends React.Component {
  state = {
    summary: {
      task: {
        completed: 0,
        failed: 0,
        exception: 0,
        running: 0,
        pending: 0,
        unscheduled: 0
      },
      image: {}
    }
  };

  constructor(props) {
    super(props);
    this.appendToSummary = this.appendToSummary.bind(this);
  }

  appendToSummary(summary) {
    this.setState(state => {
      let combined = {
        task: {
          completed: state.summary.task.completed + summary.task.completed,
          failed: state.summary.task.failed + summary.task.failed,
          exception: state.summary.task.exception + summary.task.exception,
          running: state.summary.task.running + summary.task.running,
          pending: state.summary.task.pending + summary.task.pending,
          unscheduled: state.summary.task.unscheduled + summary.task.unscheduled
        },
        image: { ...state.summary.image, ...summary.image }
      };
      this.props.appender(combined);
      return { summary: combined };
    });
  }

  render() {
    return (
      <ul>
        {
          this.props.runs.map(run => (
            <Run run={run} key={run.runId} taskId={this.props.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
          ))
        }
      </ul>
    );
  }
}

export default Runs;

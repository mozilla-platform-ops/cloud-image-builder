import React from 'react'
import Runs from './Runs';

class Task extends React.Component {
  state = {
    summary: {
      task: {
        completed: {},
        failed: {},
        exception: {},
        running: {},
        pending: {},
        unscheduled: {}
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
          completed: { ...state.summary.task.completed, ...summary.task.completed },
          failed: { ...state.summary.task.failed, ...summary.task.failed },
          exception: { ...state.summary.task.exception, ...summary.task.exception },
          running: { ...state.summary.task.running, ...summary.task.running },
          pending: { ...state.summary.task.pending, ...summary.task.pending },
          unscheduled: { ...state.summary.task.unscheduled, ...summary.task.unscheduled }
        },
        image: { ...state.summary.image, ...summary.image }
      };
      this.props.appender(combined);
      return { summary: combined };
    });
  }

  render() {
    return (
      <li>
        {this.props.task.task.metadata.name}
        &nbsp;
        <a href={this.props.rootUrl + '/tasks/' + this.props.task.status.taskId} title={this.props.task.status.taskId}>
          {this.props.task.status.taskId.substring(0, 7)}...
        </a>
        <Runs runs={this.props.task.status.runs} taskId={this.props.task.status.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
      </li>
    );
  }
}

export default Task;

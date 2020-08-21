import React from 'react'
import Runs from './Runs';
import StatusBadgeVariantMap from './StatusBadgeVariantMap';
import Badge from 'react-bootstrap/Badge';

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
    if (['01', '02'].includes(this.props.task.task.metadata.name.slice(0, 2))) {
      return (
        <li style={{listStyleType: 'none', margin: 0, padding: 0}}>
          <h6>{this.props.task.task.metadata.name}</h6>
          <a href={this.props.rootUrl + '/tasks/' + this.props.task.status.taskId} title={this.props.task.status.taskId}>
            {this.props.task.status.taskId}
          </a>
          {
            Array.from(new Set(this.props.task.status.runs.map(r => r.state))).map(state => (
              <Badge
                key={state}
                style={{ margin: '0 1px' }}
                variant={StatusBadgeVariantMap[state]}
                title={state + ': ' + this.props.task.status.runs.filter(r => r.state === state).length}>
                {this.props.task.status.runs.filter(r => r.state === state).length}
              </Badge>
            ))
          }
          <hr />
          <Runs runs={this.props.task.status.runs} taskId={this.props.task.status.taskId} taskName={this.props.task.task.metadata.name} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
        </li>
      );
    } else {
      return (
        <li>
          {this.props.task.task.metadata.name}
          &nbsp;
          <a href={this.props.rootUrl + '/tasks/' + this.props.task.status.taskId} title={this.props.task.status.taskId}>
            {this.props.task.status.taskId}
          </a>
          {
            Array.from(new Set(this.props.task.status.runs.map(r => r.state))).map(state => (
              <Badge
                key={state}
                style={{ margin: '0 1px' }}
                variant={StatusBadgeVariantMap[state]}
                title={state + ': ' + this.props.task.status.runs.filter(r => r.state === state).length}>
                {this.props.task.status.runs.filter(r => r.state === state).length}
              </Badge>
            ))
          }
          <hr />
          <Runs runs={this.props.task.status.runs} taskId={this.props.task.status.taskId} taskName={this.props.task.task.metadata.name} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
        </li>
      );
    }
  }
}

export default Task;

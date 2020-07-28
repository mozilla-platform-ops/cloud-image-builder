import React from 'react'
import Task from './Task';

class Tasks extends React.Component {
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
      <ul>
        {
          this.props.tasks.sort((a, b) => ((a.task.metadata.name < b.task.metadata.name) ? -1 : (a.task.metadata.name > b.task.metadata.name) ? 1 : 0)).filter(t => (!this.props.settings.limit.tasks || this.props.settings.limit.tasks.includes(t.task.metadata.name.slice(0, 2)))).map(task => (
            <Task task={task} key={task.status.taskId} rootUrl={this.props.rootUrl} appender={this.appendToSummary} />
          ))
        }
      </ul>
    );
  }
}

export default Tasks;

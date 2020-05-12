import React from 'react'
import Status from './Status';

class Statuses extends React.Component {
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
          this.props.contexts.map((context, cI) => (
            <li key={cI}>
              { context }
              <ul>
              {
                // only show pending statuses if there are no others (eg: failed/completed)
                (this.props.statuses.some(s => s.context === context && s.state !== 'pending'))
                  ? this.props.statuses.filter(s => s.context === context && s.state !== 'pending').map((status) => (
                    <Status status={status} key={status.id} appender={this.appendToSummary} settings={this.props.settings} />
                  ))
                  : this.props.statuses.filter(s => s.context === context).map((status) => (
                    <Status status={status} key={status.id} appender={this.appendToSummary} settings={this.props.settings} />
                  ))
              }
              </ul>
            </li>
          ))
        }
      </ul>
    );
  }
}

export default Statuses;

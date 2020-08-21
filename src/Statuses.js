import React from 'react'
import Tab from 'react-bootstrap/Tab';
import Tabs from 'react-bootstrap/Tabs';
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
      <Tabs transition={null} defaultActiveKey="0">
        {
          this.props.contexts.reverse().map((context, cI) => (
            <Tab
              key={cI}
              eventKey={cI}
              title={
                <>
                  <img style={{width: '30px', height: '30px', marginRight: '1em'}} src={this.props.statuses.find(s => s.context === context).avatar_url} alt={context} />
                  <span>{context}</span>
                </>
              }>
              {
                // only show pending statuses if there are no others (eg: failed/completed)
                (this.props.statuses.some(s => s.context === context && s.state !== 'pending'))
                  ? this.props.statuses.filter(s => s.context === context && s.state !== 'pending').map((status) => (
                    <Status status={status} key={status.id} appender={this.appendToSummary} settings={this.props.settings} />
                  ))
                  // todo: add a reducer below to remove duplicate pending statuses
                  : this.props.statuses.filter(s => s.context === context).map((status) => (
                    <Status status={status} key={status.id} appender={this.appendToSummary} settings={this.props.settings} />
                  ))
              }
            </Tab>
          ))
        }
      </Tabs>
    );
  }
}

export default Statuses;

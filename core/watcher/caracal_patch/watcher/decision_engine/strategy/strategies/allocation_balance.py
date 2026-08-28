# CubeCOS: rebalance by allocation (compute model only, no metrics datasource),
# so idle instances spread evenly where utilization-based strategies do nothing.

from oslo_log import log

from watcher._i18n import _
from watcher.decision_engine.strategy.strategies import base

LOG = log.getLogger(__name__)


class AllocationBalance(base.WorkloadStabilizationBaseStrategy):
    """Balance instances across compute nodes by allocated resources."""

    def __init__(self, config, osc=None):
        super(AllocationBalance, self).__init__(config, osc)
        self._metric = 'instance'
        self.instance_migrations_count = 0

    @classmethod
    def get_name(cls):
        return "allocation_balance"

    @classmethod
    def get_display_name(cls):
        return _("Allocation Balance Strategy")

    @classmethod
    def get_translatable_display_name(cls):
        return "Allocation Balance Strategy"

    @classmethod
    def get_schema(cls):
        return {
            "properties": {
                "metric": {
                    "description": ("balance by 'instance' count, 'vcpu' or "
                                    "'memory' allocation"),
                    "type": "string",
                    "default": "instance",
                    "enum": ["instance", "vcpu", "memory"],
                },
            },
        }

    def _load(self, node):
        """Allocated load on a node for the selected metric."""
        if self._metric == 'instance':
            return len(self.compute_model.get_node_instances(node))
        free = self.compute_model.get_node_free_resources(node)
        if self._metric == 'vcpu':
            return node.vcpus - free['vcpu']
        return node.memory - free['memory']

    def _size(self, inst):
        if self._metric == 'vcpu':
            return inst.vcpus
        if self._metric == 'memory':
            return inst.memory
        return 1

    def _fits(self, node, inst):
        free = self.compute_model.get_node_free_resources(node)
        return free['vcpu'] >= inst.vcpus and free['memory'] >= inst.memory

    def pre_execute(self):
        self._pre_execute()
        self._metric = self.input_parameters.get('metric', 'instance')

    def do_execute(self, audit=None):
        nodes = list(self.compute_model.get_all_compute_nodes().values())
        if len(nodes) < 2:
            LOG.info("allocation_balance: fewer than 2 compute nodes")
            return
        # Greedy: move one instance at a time, most- to least-allocated node,
        # only while the move shrinks the spread (prevents ping-pong); capped.
        for _step in range(1000):
            nodes.sort(key=self._load)
            dest = nodes[0]
            src = nodes[-1]
            spread = self._load(src) - self._load(dest)
            movable = None
            for inst in sorted(self.compute_model.get_node_instances(src),
                               key=self._size):
                if self._size(inst) < spread and self._fits(dest, inst):
                    movable = inst
                    break
            if movable is None:
                break
            if self.compute_model.migrate_instance(movable, src, dest):
                self.add_action_migrate(movable, 'live', src, dest)
                self.instance_migrations_count += 1
        LOG.info("allocation_balance: %d migration(s) planned (metric=%s)",
                 self.instance_migrations_count, self._metric)

    def post_execute(self):
        self.solution.model = self.compute_model
        self.solution.set_efficacy_indicators(
            instance_migrations_count=self.instance_migrations_count,
            instances_count=len(self.compute_model.get_all_instances()))
        LOG.debug(self.compute_model.to_string())

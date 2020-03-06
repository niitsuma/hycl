import hy.models
from colorama import Fore
from hy import _initialize_env_var

PRETTY = True
COLORED = _initialize_env_var('HY_COLORED_AST_OBJECTS', False)

class _ColoredModel:
    """
    Mixin that provides a helper function for models that have color.
    """

    def _colored(self, text):
        if COLORED:
            return self.color + text + Fore.RESET
        else:
            return text
        
#class hyclsequence(hy.models.HyObject, list, _ColoredModel):
#class hyclsequence(hy.models.HyKeyword, list):
#class hyclsequence(hy.models.HyList):
#class hyclsequence( list, _ColoredModel):
class hyclsequence( list):

    # __properties__ = ["module", "start_line", "end_line", "start_column",
    #                   "end_column"]

    def replace(self, other, recursive=True):
        if recursive:
            for x in self:
                hy.models.replace_hy_obj(x, other)
        hy.models.HyObject.replace(self, other)
        return self

    # def __add__(self, other):
    #     return self.__class__(super(hyclsequence, self).__add__(
    #         tuple(other) if isinstance(other, list) else other))
    def __add__(self, other):
        return self.__class__(super(hyclsequence, self).__add__(other))
    
    def __getslice__(self, start, end):
        return self.__class__(super(hyclsequence, self).__getslice__(start, end))

    def __getitem__(self, item):
        ret = super(hyclsequence, self).__getitem__(item)

        if isinstance(item, slice):
            return self.__class__(ret)

        return ret

    # color = None
    
    # def __repr__(self):
    #     return str(self) if PRETTY else super(hyclqequence, self).__repr__()

    # def __str__(self):
    #     with hy.models.pretty():
    #         if self:
    #             return self._colored("{}{}\n  {}{}".format(
    #                 self._colored(self.__class__.__name__),
    #                 self._colored("(["),
    #                 self._colored(",\n  ").join(map(hy.models.repr_indent, self)),
    #                 self._colored("])"),
    #             ))
    #             return self._colored("{}([\n  {}])".format(
    #                 self.__class__.__name__,
    #                 ','.join(hy.models.repr_indent(e) for e in self),
    #             ))
    #         else:
    #             return self._colored(self.__class__.__name__ + "()")

# class hyclvector(hy.models.HyList):
#     pass
# class hycllist(hy.models.HyList):
#     pass

class hycllist(hyclsequence):
    color = Fore.CYAN
            
class hyclvector(hyclsequence):
   color = Fore.CYAN
